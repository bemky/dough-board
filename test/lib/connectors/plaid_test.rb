require "test_helper"

# Exercises the connector against the Plaid SDK's own response objects, built
# from the shapes the live sandbox actually returns (see `bin/rails plaid:sandbox`
# for the same path against the real API). Using the real model classes rather
# than stubs is the point: a field renamed in the gem fails here instead of in
# production.
class Connectors::PlaidTest < ActiveSupport::TestCase

  # Stands in for Plaid::PlaidApi. Each method returns whatever was handed to it,
  # or raises, and records the request so the test can assert on what was asked.
  class FakeApi
    attr_reader :requests
    attr_accessor :accounts_response, :holdings_response, :transactions_responses,
      :link_token_response, :exchange_response, :error

    def initialize
      @requests = Hash.new { |hash, key| hash[key] = [] }
      @transactions_responses = []
    end

    %i[accounts_get investments_holdings_get link_token_create
      item_public_token_exchange item_remove].each do |method|
      define_method(method) do |request|
        @requests[method] << request
        raise @error if @error
        case method
        when :accounts_get then @accounts_response
        when :investments_holdings_get then @holdings_response
        when :link_token_create then @link_token_response
        when :item_public_token_exchange then @exchange_response
        else true
        end
      end
    end

    def investments_transactions_get(request)
      @requests[:investments_transactions_get] << request
      raise @error if @error
      @transactions_responses.shift
    end
  end

  setup do
    @api = FakeApi.new
    @connector = Connectors::Plaid.send(:instance)
    @connector.instance_variable_set(:@client, @api)

    @connection = Connection.create!(connector: "plaid", foreign_id: "item-1",
      financial_institution: "Vanguard", credentials: {"access_token" => "access-1"})
    @account = Account.create!(name: "Plaid 401k", connection: @connection,
      foreign_id: "acct-invest", positions_source: "connection")
  end

  teardown do
    # The connector is a singleton, so a client left behind would outlive the test.
    @connector.remove_instance_variable(:@client)
  end

  # --- fixtures -------------------------------------------------------------

  def account(id:, type:, subtype: nil, name: "An account", mask: "0000",
    current: 100.0, currency: "USD")
    ::Plaid::AccountBase.new(
      account_id: id, type: type, subtype: subtype, name: name, mask: mask,
      balances: ::Plaid::AccountBalance.new(current: current, iso_currency_code: currency)
    )
  end

  def security(id:, ticker: nil, type: "equity", name: "A security", **rest)
    ::Plaid::Security.new(security_id: id, ticker_symbol: ticker, type: type, name: name, **rest)
  end

  def holding(account_id:, security_id:, quantity:, price:, cost_basis: nil, currency: "USD")
    ::Plaid::Holding.new(
      account_id: account_id, security_id: security_id, quantity: quantity,
      institution_price: price, institution_value: quantity * price,
      cost_basis: cost_basis, iso_currency_code: currency
    )
  end

  def activity(id:, type:, subtype:, quantity:, security_id: nil, amount: 0.0, date: "2026-08-20")
    ::Plaid::InvestmentTransaction.new(
      investment_transaction_id: id, account_id: "acct-invest", security_id: security_id,
      date: date, type: type, subtype: subtype, quantity: quantity, amount: amount,
      price: 1.0, fees: 0.0, name: "#{type} #{subtype}"
    )
  end

  def accounts_response(*accounts, institution: "Vanguard")
    ::Plaid::AccountsGetResponse.new(
      accounts: accounts, request_id: "req",
      item: ::Plaid::Item.new(item_id: "item-1", institution_id: "ins_1", institution_name: institution)
    )
  end

  def holdings_response(holdings:, securities:)
    ::Plaid::InvestmentsHoldingsGetResponse.new(
      accounts: [], holdings: holdings, securities: securities, request_id: "req"
    )
  end

  def transactions_response(activities, securities: [], total: nil)
    ::Plaid::InvestmentsTransactionsGetResponse.new(
      accounts: [], securities: securities, investment_transactions: activities,
      total_investment_transactions: total || activities.length, request_id: "req"
    )
  end

  def api_error(code, message = "something went wrong")
    ::Plaid::ApiError.new(
      code: 400,
      response_body: {error_code: code, error_message: message, display_message: nil}.to_json
    )
  end

  # --- accounts -------------------------------------------------------------

  test "accounts keeps the ones a portfolio can hold and drops the debts" do
    @api.accounts_response = accounts_response(
      account(id: "acct-invest", type: "investment", subtype: "401k", name: "Plaid 401k", mask: "6666"),
      account(id: "acct-bank", type: "depository", subtype: "checking", name: "Plaid Checking"),
      account(id: "acct-card", type: "credit", subtype: "credit card"),
      account(id: "acct-loan", type: "loan", subtype: "mortgage")
    )

    accounts = Connectors::Plaid.accounts(@connection)

    assert_equal %w[acct-invest acct-bank], accounts.map { |a| a[:foreign_id] }
    assert_equal({foreign_id: "acct-invest", name: "Plaid 401k", number: "6666",
      institution_name: "Vanguard"}, accounts.first)
  end

  # --- cash -----------------------------------------------------------------

  test "cash is a bank account's balance and nothing for a brokerage" do
    @api.accounts_response = accounts_response(
      account(id: "acct-bank", type: "depository", current: 12060.0),
      account(id: "acct-invest", type: "investment", current: 23631.98)
    )
    bank = Account.create!(name: "Checking", connection: @connection,
      foreign_id: "acct-bank", positions_source: "connection")

    assert_equal 12060.0, Connectors::Plaid.cash(@connection, bank)
    # An investment account's cash arrives as a holding instead, and counting the
    # account's whole value as cash would double the account.
    assert_nil Connectors::Plaid.cash(@connection, @account)
  end

  test "cash ignores a balance denominated in something other than dollars" do
    @api.accounts_response = accounts_response(
      account(id: "acct-bank", type: "depository", current: 900.0, currency: "GBP")
    )
    bank = Account.create!(name: "Checking", connection: @connection,
      foreign_id: "acct-bank", positions_source: "connection")

    assert_nil Connectors::Plaid.cash(@connection, bank)
  end

  # --- positions ------------------------------------------------------------

  test "positions map holdings to Dough Board's own vocabulary" do
    @api.holdings_response = holdings_response(
      holdings: [holding(account_id: "acct-invest", security_id: "sec-ewz", quantity: 5.0,
        price: 42.15, cost_basis: 200.0)],
      securities: [security(id: "sec-ewz", ticker: "EWZ", type: "etf",
        name: "iShares Inc MSCI Brazil", market_identifier_code: "XNAS", figi: "BBG000")]
    )

    position = Connectors::Plaid.positions(@connection, @account).sole

    assert_equal "EWZ", position[:symbol]
    assert_equal "fund", position[:type]
    assert_equal "XNAS", position[:exchange_mic]
    assert_equal "BBG000", position[:figi_code]
    assert_equal 5.0, position[:units]
    assert_equal 42.15, position[:price]
    # Plaid's cost_basis is the total for the whole holding — SnapTrade's is per
    # unit — so 200 over 5 shares is 40 apiece.
    assert_equal 40.0, position[:average_price]
  end

  test "positions ask only about the account being synced" do
    @api.holdings_response = holdings_response(holdings: [], securities: [])

    Connectors::Plaid.positions(@connection, @account)

    request = @api.requests[:investments_holdings_get].sole
    assert_equal ["acct-invest"], request.options.account_ids
  end

  test "positions carry a cash holding as the dollar asset, not a new instrument" do
    @api.holdings_response = holdings_response(
      # Plaid names it "U S Dollar" and gives it no ticker at all.
      holdings: [holding(account_id: "acct-invest", security_id: "sec-usd",
        quantity: 12345.67, price: 1.0)],
      securities: [security(id: "sec-usd", ticker: nil, type: "cash", name: "U S Dollar")]
    )

    position = Connectors::Plaid.positions(@connection, @account).sole

    assert_equal "USD", position[:symbol]
    assert_equal "cash", position[:type]
    assert_equal 12345.67, position[:units]
  end

  test "positions leave out cash that isn't dollars" do
    @api.holdings_response = holdings_response(
      holdings: [holding(account_id: "acct-invest", security_id: "sec-eur",
        quantity: 500.0, price: 1.0, currency: "EUR")],
      securities: [security(id: "sec-eur", type: "cash", name: "Euro")]
    )

    assert_empty Connectors::Plaid.positions(@connection, @account)
  end

  test "a security with no ticker still counts, under whatever identifier there is" do
    @api.holdings_response = holdings_response(
      holdings: [
        holding(account_id: "acct-invest", security_id: "sec-cusip", quantity: 10.0, price: 94.8),
        holding(account_id: "acct-invest", security_id: "sec-none", quantity: 21.5, price: 20.0)
      ],
      securities: [
        security(id: "sec-cusip", ticker: nil, type: "fixed income", cusip: "912796YS7"),
        security(id: "sec-none", ticker: nil, type: "mutual fund", name: "Trp Equity Income")
      ]
    )

    positions = Connectors::Plaid.positions(@connection, @account)

    # A holding dropped for want of a ticker would silently understate the
    # portfolio, which matters more than a tidy symbol.
    assert_equal ["912796YS7", "PLAID:sec-none"], positions.map { |p| p[:symbol] }
    assert_equal [948.0, 430.0], positions.map { |p| p[:units] * p[:price] }
  end

  test "an institution with no brokerage behind it has no holdings, not an error" do
    @api.error = api_error("PRODUCTS_NOT_SUPPORTED", "products not supported")

    assert_empty Connectors::Plaid.positions(@connection, @account)
  end

  # --- transactions ---------------------------------------------------------

  test "transactions read the subtype, which is the precise one" do
    securities = [security(id: "sec-sbsi", ticker: "SBSI")]
    @api.transactions_responses = [transactions_response([
      activity(id: "t1", type: "buy", subtype: "buy", quantity: 3.0, security_id: "sec-sbsi"),
      activity(id: "t2", type: "cash", subtype: "qualified dividend", quantity: 0.0, security_id: "sec-sbsi"),
      activity(id: "t3", type: "cash", subtype: "dividend reinvestment", quantity: 1.5, security_id: "sec-sbsi"),
      activity(id: "t4", type: "fee", subtype: "account fee", quantity: 3.0)
    ], securities: securities)]

    types = Connectors::Plaid.transactions(@connection, @account).map { |t| t[:type] }

    assert_equal %w[buy dividend rei fee], types
  end

  test "a sale keeps a positive quantity, because UNIT_SIGNS applies the direction" do
    @api.transactions_responses = [transactions_response([
      activity(id: "t1", type: "sell", subtype: "sell", quantity: -430.8),
      # A transfer is reported in both directions under the one type, so the
      # sign is the only thing saying which way it went.
      activity(id: "t2", type: "transfer", subtype: "transfer", quantity: -12.0)
    ])]

    rows = Connectors::Plaid.transactions(@connection, @account)

    assert_equal 430.8, rows.first[:quantity]
    assert_equal(-1 * 430.8, Transaction::UNIT_SIGNS["sale"] * rows.first[:quantity])
    assert_equal(-12.0, rows.second[:quantity])
  end

  test "a cancelled transaction is left alone rather than applied as a trade" do
    @api.transactions_responses = [transactions_response([
      activity(id: "t1", type: "cancel", subtype: "cancel", quantity: 3.0),
      activity(id: "t2", type: "buy", subtype: "buy", quantity: 3.0)
    ])]

    assert_equal ["t2"], Connectors::Plaid.transactions(@connection, @account).map { |t| t[:foreign_id] }
  end

  test "transactions walk every page rather than taking the first" do
    @api.transactions_responses = [
      transactions_response([activity(id: "t1", type: "buy", subtype: "buy", quantity: 1.0)], total: 2),
      transactions_response([activity(id: "t2", type: "buy", subtype: "buy", quantity: 1.0)], total: 2)
    ]

    rows = Connectors::Plaid.transactions(@connection, @account)

    assert_equal %w[t1 t2], rows.map { |t| t[:foreign_id] }
    assert_equal [0, 1], @api.requests[:investments_transactions_get].map { |r| r.options.offset }
  end

  test "transactions start from the last sync, and go back two years without one" do
    @api.transactions_responses = [transactions_response([]), transactions_response([])]

    Connectors::Plaid.transactions(@connection, @account, since: Time.utc(2026, 8, 1))
    Connectors::Plaid.transactions(@connection, @account)

    requests = @api.requests[:investments_transactions_get]
    assert_equal "2026-08-01", requests.first.start_date
    assert_equal 2.years.ago.to_date.to_s, requests.second.start_date
  end

  # --- connecting -----------------------------------------------------------

  test "there is nothing to discover, and the UI is told so" do
    assert_not Connectors::Plaid.discoverable?
    assert Connectors::Plaid.linkable?
    assert_raises(Connectors::ConnectionError) { Connectors::Plaid.authorizations }
  end

  test "a link token asks for investments; one for a connection updates it in place" do
    @api.link_token_response = ::Plaid::LinkTokenCreateResponse.new(
      link_token: "link-sandbox-1", expiration: Time.current, request_id: "req"
    )

    assert_equal "link-sandbox-1", Connectors::Plaid.link_token
    assert_equal "link-sandbox-1", Connectors::Plaid.link_token(@connection)

    fresh, update = @api.requests[:link_token_create]
    assert_equal ["investments"], fresh.products
    assert_nil fresh.access_token
    # Update mode reauthenticates the Item already on hand rather than making one.
    assert_equal "access-1", update.access_token
    assert_nil update.products
  end

  test "connecting trades the one-time token for the connection's own credentials" do
    @api.exchange_response = ::Plaid::ItemPublicTokenExchangeResponse.new(
      access_token: "access-2", item_id: "item-2", request_id: "req"
    )
    @api.accounts_response = accounts_response(institution: "Wells Fargo")

    attributes = Connectors::Plaid.connect!("public-sandbox-1")

    assert_equal "item-2", attributes[:foreign_id]
    assert_equal({"access_token" => "access-2"}, attributes[:credentials])
    assert_equal "Wells Fargo", attributes[:financial_institution]
    assert_equal "ins_1", attributes[:financial_institution_slug]
  end

  test "disconnecting releases the Item, because a plan is capped by them" do
    assert Connectors::Plaid.disconnect!(@connection)
    assert_equal "access-1", @api.requests[:item_remove].sole.access_token
  end

  test "disconnecting an Item Plaid has already lost still lets the row go" do
    @api.error = api_error("ITEM_NOT_FOUND")

    assert_not Connectors::Plaid.disconnect!(@connection)
  end

  test "a connection with no access token says so instead of asking Plaid" do
    @connection.update!(credentials: nil)

    error = assert_raises(Connectors::ConnectionError) { Connectors::Plaid.accounts(@connection) }
    assert_match "reconnect", error.message
    assert_empty @api.requests
  end

  # --- errors ---------------------------------------------------------------

  test "a Plaid failure is reported in Plaid's own words, with its code" do
    @api.error = api_error("ITEM_LOGIN_REQUIRED", "the login details of this item have changed")

    error = assert_raises(Connectors::ConnectionError) { Connectors::Plaid.accounts(@connection) }

    assert_equal "ITEM_LOGIN_REQUIRED", error.code
    assert_match "the login details of this item have changed", error.message
  end

  test "the sandbox shortcut refuses to run against production" do
    @connector.define_singleton_method(:environment) { "production" }
    assert_raises(Connectors::ConnectionError) { Connectors::Plaid.sandbox_public_token("ins_1") }
  ensure
    @connector.singleton_class.remove_method(:environment)
  end

end
