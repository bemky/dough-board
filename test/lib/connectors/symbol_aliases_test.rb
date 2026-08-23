require "test_helper"

# One instrument, one name. A venue's private spelling has to be translated
# before it leaves the connector, or it becomes a second asset downstream — its
# own portfolio tile, its own cost basis, and no quote, since Finnhub has never
# heard of BINANCE:XXBTUSDT.
class Connectors::SymbolAliasesTest < ActiveSupport::TestCase

  test "a venue's spelling becomes the name Dough Board knows" do
    assert_equal "BTC", canonical("XXBT")
    assert_equal "DOGE", canonical("XXDG")
    assert_equal "USD", canonical("ZUSD")
  end

  test "an unmapped symbol passes through untouched" do
    assert_equal "BTC", canonical("BTC")
    # Kraken only prefixes its older listings, so a rule that stripped a leading
    # X would mangle the coins it leaves alone.
    assert_equal "XTZ", canonical("XTZ")
    assert_equal "PLAID:abc123", canonical("PLAID:abc123")
  end

  test "matching ignores case, and a blank symbol stays blank" do
    assert_equal "BTC", canonical("xxbt")
    assert_nil canonical(nil)
    assert_equal "", canonical("")
  end

  test "SnapTrade normalizes the symbols on positions and activities" do
    connector = Connectors::SnapTrade.send(:instance)
    connector.instance_variable_set(:@client, SnapTradeClient.new)

    position = connector.positions(connection, account).sole
    assert_equal "BTC", position[:symbol]

    activity = connector.transactions(connection, account).sole
    assert_equal "BTC", activity[:symbol]
  end

  test "Plaid normalizes a security's ticker" do
    connector = Connectors::Plaid.send(:instance)
    security = ::Plaid::Security.new(security_id: "sec-1", ticker_symbol: "XXBT",
      type: "cryptocurrency", name: "Bitcoin")

    assert_equal "BTC", connector.send(:symbol_for, security)
  end

  private

  def canonical(symbol)
    Connectors::Base.send(:instance).canonical_symbol(symbol)
  end

  def connection
    @connection ||= Connection.create!(connector: "snaptrade", foreign_id: "auth-1",
      financial_institution: "Kraken")
  end

  def account
    @account ||= Account.create!(name: "Kraken", connection: connection,
      foreign_id: "acct-1", positions_source: "connection")
  end

  # The SnapTrade SDK's responses are open structs of nested objects; these are
  # the shapes the connector reads, filled in with what Kraken actually reports.
  InstrumentRow = Struct.new(:symbol, :description, :kind, :exchange, :currency,
    :figi_instrument, keyword_init: true)
  PositionRow = Struct.new(:instrument, :units, :price, :cost_basis, keyword_init: true)
  ActivitySymbol = Struct.new(:raw_symbol, :symbol, keyword_init: true)
  ActivityRow = Struct.new(:id, :symbol, :type, :trade_date, :settlement_date, :units,
    :amount, keyword_init: true)

  class SnapTradeClient
    def account_information = self

    def get_all_account_positions(**)
      Struct.new(:results).new([
        PositionRow.new(
          instrument: InstrumentRow.new(symbol: "XXBT", description: "Bitcoin",
            kind: "crypto", exchange: "KRAK", currency: "USD"),
          units: 0.5, price: 60_000.0, cost_basis: 40_000.0
        )
      ])
    end

    def get_account_activities(**)
      Struct.new(:data, :pagination).new(
        [ActivityRow.new(id: "act-1", symbol: ActivitySymbol.new(raw_symbol: "XXBT"),
          type: "BUY", trade_date: Time.current, units: 0.5, amount: -20_000.0)],
        Struct.new(:total).new(1)
      )
    end
  end
end
