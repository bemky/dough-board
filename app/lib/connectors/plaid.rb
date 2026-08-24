require "plaid"

module Connectors
  # Plaid (https://plaid.com) links banks and brokerages, and reports the
  # balances and investment holdings behind them.
  #
  # Unlike SnapTrade there is nothing to discover: Plaid has no endpoint that
  # lists what a client_id is connected to. Each connection is an **Item**, and
  # the only way to make one is to run Plaid Link in the browser, which hands
  # back a short-lived public_token that #connect! trades for a permanent access
  # token. That token is the connection's own secret, so it lives on
  # `connections.credentials` rather than in config/credentials.yml — see
  # ConnectionsController#link.
  #
  # Every `::Plaid` below is deliberately root-scoped: inside this class, a bare
  # `Plaid::` would resolve to Connectors::Plaid.
  class Plaid < Base

    # security.type -> Asset#type. "derivative" and "fixed income" have real
    # value and stay as positions, but they aren't a category Dough Board quotes,
    # so they map to nil the way SnapTrade's "other" does.
    ASSET_TYPES = {
      "cash" => "cash",
      "cryptocurrency" => "crypto",
      "equity" => "stock",
      "etf" => "fund",
      "mutual fund" => "fund"
    }.freeze

    # investment_transaction.subtype -> Transaction type. Subtype is the precise
    # one (`type` only distinguishes buy/sell/cash/fee/transfer/cancel), so it's
    # what's matched first; TYPES_BY_TYPE below catches anything Plaid adds later.
    #
    # Only subtypes with a Dough Board equivalent are here. An unmapped one falls
    # through to its type, and a transaction that matches neither is skipped —
    # for a connected account transactions are history to browse, not the source
    # of its holdings, so dropping one costs nothing but a row in a table.
    TYPES_BY_SUBTYPE = {
      "buy" => "buy",
      "buy to cover" => "buy",
      "sell" => "sale",
      "sell short" => "sale",
      "dividend" => "dividend",
      "qualified dividend" => "dividend",
      "non-qualified dividend" => "dividend",
      "long-term capital gain" => "dividend",
      "short-term capital gain" => "dividend",
      "unqualified gain" => "dividend",
      "dividend reinvestment" => "rei",
      "interest reinvestment" => "rei",
      "long-term capital gain reinvestment" => "rei",
      "short-term capital gain reinvestment" => "rei",
      "stock distribution" => "stock_dividend",
      "contribution" => "contribution",
      "deposit" => "contribution",
      "withdrawal" => "withdrawal",
      "distribution" => "withdrawal",
      "interest" => "interest",
      "interest receivable" => "interest",
      "account fee" => "fee",
      "fund fee" => "fee",
      "legal fee" => "fee",
      "management fee" => "fee",
      "miscellaneous fee" => "fee",
      "transfer fee" => "fee",
      "trust fee" => "fee",
      "margin expense" => "fee",
      "tax" => "tax",
      "tax withheld" => "tax",
      "non-resident tax" => "tax",
      "assignment" => "optionassignment",
      "exercise" => "optionexercise",
      "expire" => "optionexpiration",
      "split" => "split",
      "adjustment" => "adjustment",
      "merger" => "adjustment",
      "spin off" => "adjustment",
      "transfer" => "transfer",
      "send" => "transfer"
    }.freeze

    # The fallback when the subtype is one of the many Plaid has that Dough Board
    # doesn't. "cancel" is deliberately absent: it reverses an earlier
    # transaction rather than being one, and applying it as a trade would double
    # the correction.
    TYPES_BY_TYPE = {
      "buy" => "buy",
      "sell" => "sale",
      "fee" => "fee",
      "transfer" => "transfer"
    }.freeze

    # The account types whose balance is money owed rather than money held.
    # They carry no holdings — the balance itself is the whole position — so
    # #positions and #transactions take a different path for them.
    DEBT_ACCOUNT_TYPES = %w[credit loan].freeze

    # The account types that hold instruments, and whose balance is therefore a
    # last resort rather than the answer — see #balance_positions.
    BROKERAGE_ACCOUNT_TYPES = %w[investment brokerage].freeze

    # Plaid reports every account behind an Item, and Dough Board wants all of
    # them: assets and debts together are what a net worth is.
    SYNCED_ACCOUNT_TYPES = (BROKERAGE_ACCOUNT_TYPES + %w[depository] + DEBT_ACCOUNT_TYPES).freeze

    # account.subtype -> the asset a debt is carried against. Debts are folded
    # by kind rather than by account, so two cards at two banks add up to one
    # "credit card" line in the portfolio and stay separate on their own account
    # pages. Anything Plaid reports that isn't here falls back to its type.
    #
    # The DEBT: prefix is what keeps these off the ticker tape — "LOAN" and
    # "AUTO" are both real symbols, and an asset named either would be quoted
    # against a company that has nothing to do with the debt.
    DEBTS_BY_SUBTYPE = {
      "credit card" => "DEBT:CREDIT_CARD",
      "paypal" => "DEBT:CREDIT_CARD",
      "line of credit" => "DEBT:LINE_OF_CREDIT",
      "overdraft" => "DEBT:LINE_OF_CREDIT",
      "auto" => "DEBT:AUTO_LOAN",
      "mortgage" => "DEBT:HOME_LOAN",
      "home equity" => "DEBT:HOME_LOAN",
      "construction" => "DEBT:HOME_LOAN",
      "student" => "DEBT:STUDENT_LOAN"
    }.freeze

    DEBTS_BY_TYPE = {"credit" => "DEBT:CREDIT_CARD", "loan" => "DEBT:LOAN"}.freeze

    # What each debt asset is called the first time it's created.
    DEBT_NAMES = {
      "DEBT:CREDIT_CARD" => "Credit Card Debt",
      "DEBT:LINE_OF_CREDIT" => "Line of Credit",
      "DEBT:AUTO_LOAN" => "Auto Loan",
      "DEBT:HOME_LOAN" => "Home Loan",
      "DEBT:STUDENT_LOAN" => "Student Loan",
      "DEBT:LOAN" => "Loan"
    }.freeze

    # Reading an Item's credit and loan accounts needs the liabilities product;
    # investments alone gets the brokerage side and, at institutions that filter
    # account selection by product, nothing else.
    #
    # They can't both simply be asked for: Link only shows institutions that
    # support *every* product in the request, and hardly any support both — the
    # sandbox's own investments institution refuses `liabilities` outright. So
    # one is required and the other is asked for only where it's supported,
    # which is what LINK_KINDS chooses between.
    PRODUCTS_BY_KIND = {
      "holdings" => ::Plaid::Products::INVESTMENTS,
      "debts" => ::Plaid::Products::LIABILITIES
    }.freeze

    PRODUCTS = PRODUCTS_BY_KIND.values.freeze

    def accounts(connection)
      response = accounts_get(connection)
      institution = response.item&.institution_name
      Array(response.accounts)
        .select { |account| SYNCED_ACCOUNT_TYPES.include?(account.type) }
        .map do |account|
          {
            foreign_id: account.account_id,
            name: account.name.presence || account.official_name,
            number: account.mask,
            institution_name: institution
          }
        end
    end

    # A bank account's whole balance is cash, and Plaid reports it on the account
    # rather than as a holding. An investment account's cash arrives through
    # #positions instead, as a holding in a security of type "cash", so this
    # returns nil for one rather than counting it twice.
    def cash(connection, account)
      plaid_account = plaid_account(connection, account)
      return unless plaid_account&.type == "depository"
      return unless dollars?(plaid_account)
      plaid_account.balances&.current
    end

    # A credit card or a loan holds nothing; its balance *is* its position, so
    # it's carried as a negative number of dollars against the asset standing in
    # for that kind of debt. Everything downstream — the snapshot, the account
    # total, the portfolio — then adds it up without knowing it's a liability.
    #
    # A brokerage that reports no holdings falls back to the same shape in the
    # other direction: some of them tell Plaid only what an account is worth.
    def positions(connection, account)
      plaid_account = plaid_account(connection, account)
      return debt_positions(plaid_account) if DEBT_ACCOUNT_TYPES.include?(plaid_account&.type)

      response = holdings_get(connection, account)
      rows = holding_positions(response)
      return rows if rows.any?

      balance_positions(connection, plaid_account)
    end

    # Plaid pages with count/offset and caps a page at 500, and reports the whole
    # total so there's something to page against. Narrowed to the one account
    # because ConnectionJob asks per account and an Item's full activity — every
    # account, two years — is thousands of rows to fetch once per account.
    def transactions(connection, account, since: nil)
      # A card's or a loan's activity is spending and payments, which is the
      # `transactions` product, not this one — asking here would only fail.
      return [] if DEBT_ACCOUNT_TYPES.include?(plaid_account(connection, account)&.type)

      collected = []
      offset = 0

      loop do
        response = call do
          client.investments_transactions_get(
            ::Plaid::InvestmentsTransactionsGetRequest.new(
              access_token: access_token(connection),
              start_date: (since&.to_date || DEFAULT_HISTORY.ago.to_date).to_s,
              end_date: Date.current.to_s,
              options: ::Plaid::InvestmentsTransactionsGetRequestOptions.new(
                account_ids: [account.foreign_id], count: PAGE_SIZE, offset: offset
              )
            )
          )
        end

        securities = Array(response.securities).index_by(&:security_id)
        page = Array(response.investment_transactions)
        collected.concat(page.filter_map { |activity| transaction_attributes(activity, securities) })

        offset += page.length
        break if page.empty? || offset >= response.total_investment_transactions.to_i
      end

      collected
    rescue ConnectionError => e
      # An institution that reports a balance and nothing else refuses this
      # endpoint the same way it refuses holdings. That's an account with no
      # activity to browse, not a failed sync — and raising here would strand
      # the whole connection over it.
      raise unless NO_HOLDINGS_ERRORS.include?(e.code)
      []
    end

    # Plaid has no endpoint that lists a client_id's Items, so there is nothing
    # to discover — connections arrive through Link. Connectors.discoverable
    # keeps the UI from offering it; this is the backstop if something calls it
    # anyway.
    def authorizations
      raise ConnectionError,
        "Plaid can't list connections. Add one with Link instead."
    end

    def discoverable?
      false
    end

    def linkable?
      true
    end

    # A short-lived token that authorizes one run of Plaid Link in the browser.
    # With a connection it opens in **update mode** against that Item's existing
    # access token — the flow for re-authenticating a connection the institution
    # has expired (ITEM_LOGIN_REQUIRED), which issues no new token because the
    # one on hand starts working again.
    def link_token(connection = nil, kind: LINK_KINDS.keys.first)
      request = {
        client_name: CLIENT_NAME,
        language: "en",
        country_codes: [::Plaid::CountryCode::US],
        user: ::Plaid::LinkTokenCreateRequestUser.new(client_user_id: CLIENT_USER_ID)
      }

      if connection
        # Update mode signs back in to the Item on hand; naming products here
        # would change what it was linked for, which isn't what a reconnect is.
        request[:access_token] = access_token(connection)
      else
        product = PRODUCTS_BY_KIND.fetch(kind.to_s) do
          raise ConnectionError, "Plaid can't link #{kind.inspect}"
        end
        # `balance` is not accepted here — Plaid initializes it alongside any
        # other product. The one product decides which institutions Link will
        # show; the rest are taken wherever the chosen institution happens to
        # support them, so a bank that does both is connected once.
        request[:products] = [product]
        request[:required_if_supported_products] = PRODUCTS - [product]
      end

      call { client.link_token_create(::Plaid::LinkTokenCreateRequest.new(**request)) }.link_token
    end

    # Trades Link's one-time public_token for the Item's permanent access token,
    # and describes the connection it belongs to. The token is the caller's to
    # store on the connection — Plaid will not hand it over twice.
    def connect!(public_token)
      exchanged = call do
        client.item_public_token_exchange(
          ::Plaid::ItemPublicTokenExchangeRequest.new(public_token: public_token)
        )
      end

      item = call do
        client.accounts_get(::Plaid::AccountsGetRequest.new(access_token: exchanged.access_token))
      end.item

      {
        foreign_id: exchanged.item_id,
        credentials: {"access_token" => exchanged.access_token},
        name: nil,
        financial_institution: item&.institution_name,
        financial_institution_slug: item&.institution_id
      }
    end

    # Ends Plaid's side of the connection. Items are what a plan is billed and
    # capped by, so a connection deleted here has to be removed there too or the
    # slot stays spent.
    def disconnect!(connection)
      return if connection.credentials.blank?
      call { client.item_remove(::Plaid::ItemRemoveRequest.new(access_token: access_token(connection))) }
      true
    rescue ConnectionError
      # The Item is already gone, or the token no longer works — either way
      # there's nothing left to release, and the row still deserves to go.
      false
    end

    # Stands in for a run of Plaid Link: the sandbox will mint a public_token for
    # a test institution without a browser, which is what makes the whole path —
    # exchange, accounts, holdings, activity, prune — testable against the real
    # API before a production Item is spent on it. See `bin/rails plaid:sandbox`.
    # Refused outside the sandbox, where the endpoint doesn't exist anyway.
    #
    # There's no Link here to negotiate products, so the institution is asked
    # what it supports first: naming one it doesn't is an outright refusal, and
    # the sandbox's investments institution and its liabilities one are not the
    # same institution.
    def sandbox_public_token(institution_id)
      raise ConnectionError, "Only the sandbox can mint a public token" unless environment == "sandbox"

      products = PRODUCTS & institution_products(institution_id)
      if products.empty?
        raise ConnectionError, "#{institution_id} supports neither holdings nor debts"
      end

      call do
        client.sandbox_public_token_create(
          ::Plaid::SandboxPublicTokenCreateRequest.new(
            institution_id: institution_id,
            initial_products: products
          )
        )
      end.public_token
    end

    def configured?
      credentials&.try(:client_id).present? && credentials&.try(:secret).present?
    end

    # Which Plaid deployment the credentials are for: "sandbox" for the test
    # institutions and fake data, "production" for the real thing.
    def environment
      credentials&.try(:environment).presence || "sandbox"
    end

    private

    # Plaid's ceiling for /investments/transactions/get.
    PAGE_SIZE = 500

    # How far back to read when a connection has never synced. Plaid's own
    # investments history is about two years.
    DEFAULT_HISTORY = 2.years

    # Dough Board values everything in dollars, so a balance in anything else
    # isn't a number it can add up.
    CURRENCY = "USD"

    # The namespace for the asset standing in for a brokerage account that
    # reports only what it's worth. See #balance_positions.
    BALANCE_PREFIX = "FUND:"

    # Shown to the account holder inside Plaid Link.
    CLIENT_NAME = "Dough Board"

    # Plaid wants an identifier for the person linking. Dough Board is
    # single-tenant — one password, one portfolio — so there is exactly one, and
    # a constant is the honest answer. (Plaid asks that it not be an email or
    # anything else identifying.)
    CLIENT_USER_ID = "dough-board"

    # Asking for holdings, or for investments activity, at an institution that
    # doesn't answer for them isn't a failure worth recording on the connection —
    # the answer is simply that there are none.
    NO_HOLDINGS_ERRORS = %w[PRODUCTS_NOT_SUPPORTED NO_INVESTMENT_ACCOUNTS].freeze

    # How long one /accounts/get answer stands in for the next. It answers for
    # the whole Item at once, but ConnectionJob asks per account — for its kind,
    # its cash and whether to read its activity — so an Item with a dozen
    # accounts would otherwise make dozens of identical calls in a burst, and
    # Plaid rate-limits per Item. Long enough to cover one sync, short enough
    # that the next one asks again.
    ACCOUNTS_TTL = 1.minute

    def initialize
      @accounts = {}
    end

    def credentials
      Rails.application.credentials.plaid
    end

    def access_token(connection)
      token = connection.credentials.try(:[], "access_token")
      raise ConnectionError, "Connection has no Plaid access token; reconnect it." if token.blank?
      token
    end

    def client
      @client ||= begin
        raise ConnectionError, "Plaid credentials are missing" unless configured?
        configuration = ::Plaid::Configuration.new
        configuration.server_index = ::Plaid::Configuration::Environment.fetch(environment) do
          raise ConnectionError, "Unknown Plaid environment #{environment.inspect}"
        end
        configuration.api_key["PLAID-CLIENT-ID"] = credentials.try(:client_id)
        configuration.api_key["PLAID-SECRET"] = credentials.try(:secret)
        ::Plaid::PlaidApi.new(::Plaid::ApiClient.new(configuration))
      end
    end

    def institution_products(institution_id)
      response = call do
        client.institutions_get_by_id(
          ::Plaid::InstitutionsGetByIdRequest.new(
            institution_id: institution_id, country_codes: [::Plaid::CountryCode::US]
          )
        )
      end
      Array(response.institution&.products).map(&:to_s)
    end

    def accounts_get(connection)
      token = access_token(connection)
      fetched_at, response = @accounts[token]
      return response if fetched_at && fetched_at > ACCOUNTS_TTL.ago

      response = call { client.accounts_get(::Plaid::AccountsGetRequest.new(access_token: token)) }
      @accounts[token] = [Time.current, response]
      response
    end

    # The Plaid side of one of our accounts. Everything an account carries that
    # isn't a holding — its type, its balance — comes from here.
    def plaid_account(connection, account)
      Array(accounts_get(connection).accounts)
        .find { |candidate| candidate.account_id == account.foreign_id }
    end

    # Dough Board values everything in dollars, so a balance in anything else
    # isn't a number it can add up.
    def dollars?(plaid_account)
      plaid_account.balances&.iso_currency_code.in?([nil, CURRENCY])
    end

    # Plaid signs a debt from the lender's side: on a credit or loan account a
    # positive `current` is what's owed, and a negative one is the lender owing
    # the account holder (an overpaid card). Negating it puts the balance on the
    # same axis as everything else Dough Board adds up, overpayments included.
    def debt_positions(plaid_account)
      balance = plaid_account.balances&.current
      return [] if balance.nil? || !dollars?(plaid_account)

      symbol = debt_symbol(plaid_account)
      [{
        symbol: symbol,
        name: DEBT_NAMES[symbol],
        type: "liability",
        units: -balance,
        price: 1.0,
        currency: CURRENCY
      }]
    end

    def holding_positions(response)
      return [] unless response
      securities = Array(response.securities).index_by(&:security_id)

      Array(response.holdings).filter_map do |holding|
        security = securities[holding.security_id]
        next unless security
        position_attributes(holding, security)
      end
    end

    # Some brokerages behind Plaid report what an account is *worth* and nothing
    # else. Titan, cleared by Apex, is one: /investments/holdings comes back with
    # no holdings for its accounts and there is no investments activity either,
    # so the balance on /accounts/get is the whole of what Plaid knows. Left
    # alone the account syncs as empty and the portfolio quietly loses all of it.
    #
    # So the balance is carried exactly the way a debt is, in the other
    # direction: one position of dollars at $1.00 apiece against an asset
    # standing in for the account. Everything downstream — the snapshot, the
    # account total, the treemap, the value history — then works on it unchanged,
    # and the day the institution does report holdings they simply win (see
    # #positions) and this row is pruned like any holding that went away.
    #
    # Two deliberate choices. It is *not* the USD cash asset: the money is
    # invested rather than uninvested, and folding it into cash would overstate
    # what's liquid across the whole portfolio. And unlike a debt — where every
    # card is one "credit card" line — the asset is per account, because two
    # managed accounts are two different things being valued, not one holding
    # held twice.
    def balance_positions(connection, plaid_account)
      return [] unless BROKERAGE_ACCOUNT_TYPES.include?(plaid_account&.type)

      balance = plaid_account.balances&.current
      return [] if balance.nil? || balance.zero? || !dollars?(plaid_account)

      [{
        symbol: balance_symbol(connection, plaid_account),
        name: balance_name(connection, plaid_account),
        type: "balance",
        units: balance,
        price: 1.0,
        currency: CURRENCY
      }]
    end

    # Namespaced for the same reason Plaid's debts are: "FUND" reads as what the
    # holding is, and the colon keeps it off the ticker tape — nothing will ever
    # quote it, and Asset#face_value? means nothing tries. The institution is
    # part of it because an account named "Individual" is named that at every
    # brokerage there is, and two of them are not one holding.
    def balance_symbol(connection, plaid_account)
      slug = [institution_name(connection), account_name(plaid_account)].compact_blank.join("-")
      "#{BALANCE_PREFIX}#{slug.presence&.parameterize&.upcase || plaid_account.account_id}"
    end

    def balance_name(connection, plaid_account)
      [institution_name(connection), account_name(plaid_account)].compact_blank.join(" ").presence ||
        "Account balance"
    end

    def account_name(plaid_account)
      plaid_account.name.presence || plaid_account.official_name.presence
    end

    def institution_name(connection)
      accounts_get(connection).item&.institution_name
    end

    def debt_symbol(plaid_account)
      DEBTS_BY_SUBTYPE[plaid_account.subtype.to_s] || DEBTS_BY_TYPE.fetch(plaid_account.type, "DEBT:LOAN")
    end

    def holdings_get(connection, account)
      call do
        client.investments_holdings_get(
          ::Plaid::InvestmentsHoldingsGetRequest.new(
            access_token: access_token(connection),
            options: ::Plaid::InvestmentHoldingsGetRequestOptions.new(account_ids: [account.foreign_id])
          )
        )
      end
    rescue ConnectionError => e
      raise unless NO_HOLDINGS_ERRORS.include?(e.code)
      nil
    end

    def position_attributes(holding, security)
      symbol = symbol_for(security)
      return if symbol.blank?
      # A cash holding in another currency is a number Dough Board can't add to
      # a dollar total, and calling it USD would overstate the account.
      return if security.type == "cash" && !holding.iso_currency_code.in?([nil, CURRENCY])

      {
        symbol: symbol,
        name: security.name,
        type: ASSET_TYPES[security.type],
        exchange_mic: security.market_identifier_code,
        figi_code: security.figi,
        units: holding.quantity,
        price: holding.institution_price,
        # Plaid's cost_basis is the total paid for the whole holding — the
        # opposite of SnapTrade's, which is the cost of one unit. Position
        # derives the total back from average_price on save.
        average_price: average_price(holding),
        currency: holding.iso_currency_code || CURRENCY
      }
    end

    def average_price(holding)
      return unless holding.cost_basis && holding.quantity.to_f.nonzero?
      holding.cost_basis / holding.quantity
    end

    # Plaid identifies a security by an opaque security_id and only sometimes
    # knows a ticker. Falling back to the public identifiers keeps a holding
    # recognizable; falling back to the security_id keeps it *counted*, which
    # matters more than a tidy symbol — a dropped holding silently understates
    # the portfolio. Nothing will quote a PLAID: symbol, so Position.portfolio
    # values it at the price Plaid reported.
    #
    # Dollars are the exception: Plaid carries them as a tickerless security
    # named "U S Dollar", and they're the cash asset Dough Board already has,
    # not a new instrument per institution.
    def symbol_for(security)
      return CURRENCY if security.type == "cash"
      canonical_symbol(
        security.ticker_symbol.presence ||
          security.cusip.presence ||
          security.isin.presence ||
          (security.security_id.presence && "PLAID:#{security.security_id}")
      )
    end

    def transaction_attributes(activity, securities)
      type = TYPES_BY_SUBTYPE[activity.subtype.to_s] || TYPES_BY_TYPE[activity.type.to_s]
      return unless type

      {
        foreign_id: activity.investment_transaction_id,
        symbol: securities[activity.security_id]&.then { |security| symbol_for(security) },
        type: type,
        executed_at: activity.transaction_datetime || activity.date,
        quantity: quantity_for(type, activity.quantity),
        value: activity.amount
      }
    end

    # Plaid signs the quantity by direction — a sale is negative — but
    # Transaction::UNIT_SIGNS applies the direction itself, so a signed quantity
    # would cancel out and a sale would add shares. Transfers are the exception:
    # they're reported both ways under the one type and Dough Board reads the
    # direction off the sign.
    def quantity_for(type, quantity)
      return quantity if type == "transfer" || quantity.nil?
      quantity.abs
    end

    # Plaid's failures are worth reporting in its own words — "the institution
    # is down for maintenance" and "this Item needs to be re-authenticated" are
    # different problems with different fixes.
    def call
      yield
    rescue ::Plaid::ApiError => e
      body = JSON.parse(e.response_body.to_s) rescue nil
      message = body&.values_at("error_message", "display_message")&.compact&.first
      raise ConnectionError.new(
        [body&.dig("error_code"), message || e.message].compact.join(": ")
          .to_s.gsub(/\s+/, " ").strip.truncate(200)
      ).tap { |error| error.code = body&.dig("error_code") }
    end

  end
end
