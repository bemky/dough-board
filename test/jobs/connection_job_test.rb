require "test_helper"

# Stands in for a real connector so the job can be tested without a network.
# Registered into Connectors::REGISTRY for the duration of each test.
class StubConnector
  class << self
    attr_accessor :accounts_data, :positions_data, :transactions_data, :cash_data, :error

    def accounts(_connection)
      raise Connectors::ConnectionError, error if error
      accounts_data || []
    end

    def cash(_connection, _account)
      cash_data
    end

    def positions(_connection, _account)
      positions_data || []
    end

    def transactions(_connection, _account, since: nil)
      @since = since
      transactions_data || []
    end

    attr_reader :since

    def reset!
      @accounts_data = @positions_data = @transactions_data = @cash_data = @error = @since = nil
    end
  end
end

class ConnectionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    StubConnector.reset!
    @original_registry = Connectors::REGISTRY
    Connectors.send(:remove_const, :REGISTRY)
    Connectors.const_set(:REGISTRY, @original_registry.merge("stub" => "StubConnector").freeze)

    @connection = Connection.create!(connector: "stub", foreign_id: "auth-1",
      financial_institution: "Testbank")

    StubConnector.accounts_data = [
      {foreign_id: "acct-1", name: "Individual", number: "X-1", institution_name: "Testbank"}
    ]
    StubConnector.positions_data = [
      {symbol: "AAPL", name: "Apple Inc", type: "stock", exchange_mic: "XNAS",
       figi_code: "BBG000B9XRY4", units: 10.0, price: 200.0, average_price: 150.0, currency: "USD"}
    ]
  end

  teardown do
    Connectors.send(:remove_const, :REGISTRY)
    Connectors.const_set(:REGISTRY, @original_registry)
  end

  test "creates the account, its asset and its position" do
    ConnectionJob.perform_now(@connection)

    account = @connection.accounts.sole
    assert_equal "Individual", account.name
    assert_equal "Testbank", account.institution_name
    assert_equal "connection", account.positions_source
    assert_not account.derives_positions?

    position = account.current_positions.sole
    assert_equal "AAPL", position.asset.symbol
    assert_in_delta 10, position.units, 0.001
    assert_in_delta 2000.0, position.value, 0.001
    # SnapTrade reports cost per unit; the total is derived from it.
    assert_in_delta 150.0, position.average_price, 0.001
    assert_in_delta 1500.0, position.cost_basis, 0.001
  end

  test "fills in the asset from the instrument, matching the exchange by MIC" do
    exchange = Exchange.create!(code: "NASDAQ", mic_code: "XNAS", name: "Nasdaq Stock Market")

    ConnectionJob.perform_now(@connection)

    asset = Asset.find_by!(symbol: "AAPL")
    assert_equal "Apple Inc", asset.name
    assert_equal "stock", asset.type
    assert_equal "BBG000B9XRY4", asset.figi_code
    assert_equal exchange, asset.exchange
  end

  test "an unknown exchange leaves the asset without one" do
    ConnectionJob.perform_now(@connection)
    assert_nil Asset.find_by!(symbol: "AAPL").exchange
  end

  test "a second run corrects the snapshot in place" do
    ConnectionJob.perform_now(@connection)
    account = @connection.accounts.sole
    first_as_of = account.positions_as_of

    StubConnector.positions_data.first[:units] = 12.0
    ConnectionJob.perform_now(@connection)

    assert_equal first_as_of, account.reload.positions_as_of
    assert_equal 1, account.positions.count
    assert_in_delta 12, account.current_positions.sole.units, 0.001
  end

  test "a run with as_of appends a point to the history" do
    ConnectionJob.perform_now(@connection)
    account = @connection.accounts.sole
    later = account.positions_as_of + 1.hour

    ConnectionJob.perform_now(@connection, as_of: later)

    assert_equal 2, account.positions.count
    assert_equal later, account.reload.positions_as_of
  end

  test "a holding the institution stops reporting leaves the snapshot" do
    StubConnector.positions_data << {symbol: "TSLA", name: "Tesla", type: "stock",
      units: 3.0, price: 400.0, currency: "USD"}
    ConnectionJob.perform_now(@connection)
    account = @connection.accounts.sole
    assert_equal 2, account.current_positions.count

    StubConnector.positions_data.pop
    ConnectionJob.perform_now(@connection)

    assert_equal %w(AAPL), account.current_positions.map { |p| p.asset.symbol }
  end

  test "cash rides along as a position against a cash asset" do
    StubConnector.cash_data = 250.0

    ConnectionJob.perform_now(@connection)
    account = @connection.accounts.sole

    cash = account.current_positions.find { |p| p.asset.symbol == "USD" }
    assert_equal "cash", cash.asset.type
    assert_in_delta 250.0, cash.units, 0.001
    assert_in_delta 250.0, cash.value, 0.001
    # 10 x $200 of AAPL, plus the cash.
    assert_in_delta 2250.0, account.value, 0.001
  end

  # The point of carrying cash as a position rather than a column on the
  # account: it belongs to one snapshot, so an older valuation reports the cash
  # of its own moment rather than today's.
  test "each snapshot keeps its own cash" do
    StubConnector.cash_data = 250.0
    ConnectionJob.perform_now(@connection)
    account = @connection.accounts.sole
    first_as_of = account.positions_as_of

    StubConnector.cash_data = 900.0
    ConnectionJob.perform_now(@connection, as_of: first_as_of + 1.hour)

    older = account.positions.where(as_of: first_as_of).find { |p| p.asset.symbol == "USD" }
    assert_in_delta 250.0, older.units, 0.001
    assert_in_delta 900.0, account.reload.current_positions.find { |p| p.asset.symbol == "USD" }.units, 0.001
  end

  test "zero cash gets no position" do
    StubConnector.cash_data = 0.0
    ConnectionJob.perform_now(@connection)
    assert_equal %w(AAPL), @connection.accounts.sole.current_positions.map { |p| p.asset.symbol }
  end

  test "transactions are upserted and deduped by foreign_id" do
    StubConnector.transactions_data = [
      {foreign_id: "act-1", symbol: "AAPL", type: "buy", executed_at: Date.new(2024, 1, 2),
       quantity: 10.0, value: 1500.0}
    ]

    assert_difference "Transaction.count", 1 do
      ConnectionJob.perform_now(@connection)
    end
    assert_no_difference "Transaction.count" do
      ConnectionJob.perform_now(@connection)
    end

    transaction = Transaction.sole
    assert_equal "buy", transaction.type
    assert_equal "AAPL", transaction.asset.symbol
  end

  test "a synced account does not queue a derivation from its transactions" do
    StubConnector.transactions_data = [
      {foreign_id: "act-1", symbol: "AAPL", type: "buy", executed_at: Date.new(2024, 1, 2),
       quantity: 10.0, value: 1500.0}
    ]

    assert_no_enqueued_jobs only: DerivePositionsJob do
      ConnectionJob.perform_now(@connection)
    end
  end

  test "later syncs only ask for activity since the last one" do
    ConnectionJob.perform_now(@connection)
    synced_at = @connection.reload.synced_at
    assert_not_nil synced_at

    ConnectionJob.perform_now(@connection)
    assert_equal synced_at.to_i, StubConnector.since.to_i
  end

  test "a failing connector records the error and re-raises" do
    StubConnector.error = "Brokerage is unreachable"

    assert_raises Connectors::ConnectionError do
      ConnectionJob.perform_now(@connection)
    end

    assert_equal "Brokerage is unreachable", @connection.reload.last_error
    assert_nil @connection.synced_at
  end

  test "a recovered sync clears the error" do
    StubConnector.error = "Brokerage is unreachable"
    assert_raises(Connectors::ConnectionError) { ConnectionJob.perform_now(@connection) }

    StubConnector.error = nil
    ConnectionJob.perform_now(@connection)

    assert_nil @connection.reload.last_error
    assert_not_nil @connection.synced_at
  end
end
