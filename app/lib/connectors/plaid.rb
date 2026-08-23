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

    # Plaid reports every account behind an Item, including the ones Dough Board
    # has nothing to say about. A credit card or a loan is a negative balance,
    # and Position.portfolio drops holdings whose units aren't positive — so
    # syncing them would create empty accounts that never show a number.
    SYNCED_ACCOUNT_TYPES = %w[investment brokerage depository].freeze

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
      plaid_account = Array(accounts_get(connection).accounts)
        .find { |candidate| candidate.account_id == account.foreign_id }
      return unless plaid_account&.type == "depository"
      return unless plaid_account.balances&.iso_currency_code.in?([nil, CURRENCY])
      plaid_account.balances&.current
    end

    def positions(connection, account)
      response = holdings_get(connection, account)
      return [] unless response

      securities = Array(response.securities).index_by(&:security_id)

      Array(response.holdings).filter_map do |holding|
        security = securities[holding.security_id]
        next unless security
        position_attributes(holding, security)
      end
    end

    # Plaid pages with count/offset and caps a page at 500, and reports the whole
    # total so there's something to page against. Narrowed to the one account
    # because ConnectionJob asks per account and an Item's full activity — every
    # account, two years — is thousands of rows to fetch once per account.
    def transactions(connection, account, since: nil)
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
    def link_token(connection = nil)
      request = {
        client_name: CLIENT_NAME,
        language: "en",
        country_codes: [::Plaid::CountryCode::US],
        user: ::Plaid::LinkTokenCreateRequestUser.new(client_user_id: CLIENT_USER_ID)
      }

      if connection
        request[:access_token] = access_token(connection)
      else
        # `balance` is not accepted here — Plaid initializes it alongside any
        # other product — so `investments` is what's asked for, and /accounts/get
        # still returns the institution's bank accounts along with the
        # brokerage ones.
        request[:products] = [::Plaid::Products::INVESTMENTS]
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
    def sandbox_public_token(institution_id)
      raise ConnectionError, "Only the sandbox can mint a public token" unless environment == "sandbox"
      call do
        client.sandbox_public_token_create(
          ::Plaid::SandboxPublicTokenCreateRequest.new(
            institution_id: institution_id,
            initial_products: [::Plaid::Products::INVESTMENTS]
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

    # Shown to the account holder inside Plaid Link.
    CLIENT_NAME = "Dough Board"

    # Plaid wants an identifier for the person linking. Dough Board is
    # single-tenant — one password, one portfolio — so there is exactly one, and
    # a constant is the honest answer. (Plaid asks that it not be an email or
    # anything else identifying.)
    CLIENT_USER_ID = "dough-board"

    # Asking for holdings at an institution that has no brokerage behind it
    # isn't a failure worth recording on the connection — the answer is simply
    # that there are none.
    NO_HOLDINGS_ERRORS = %w[PRODUCTS_NOT_SUPPORTED NO_INVESTMENT_ACCOUNTS].freeze

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

    def accounts_get(connection)
      call { client.accounts_get(::Plaid::AccountsGetRequest.new(access_token: access_token(connection))) }
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
      security.ticker_symbol.presence ||
        security.cusip.presence ||
        security.isin.presence ||
        (security.security_id.presence && "PLAID:#{security.security_id}")
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
