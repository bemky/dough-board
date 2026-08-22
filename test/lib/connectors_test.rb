require "test_helper"

class ConnectorsTest < ActiveSupport::TestCase

  class Echo < Connectors::Base
    def transactions(connection, account, since: nil)
      {connection: connection, account: account, since: since}
    end
  end

  test "for resolves a registered connector" do
    assert_equal Connectors::SnapTrade, Connectors.for("snaptrade")
  end

  test "for rejects an unknown connector" do
    assert_raises(ArgumentError) { Connectors.for("nope") }
  end

  # Without **kwargs on method_missing, Ruby 3 collects a call's keywords into a
  # positional Hash and this arrives as three positional arguments.
  test "class-level delegation carries keyword arguments through" do
    result = Echo.transactions(:a_connection, :an_account, since: :a_time)
    assert_equal({connection: :a_connection, account: :an_account, since: :a_time}, result)
  end

  test "the base interface refuses to guess" do
    assert_raises(NotImplementedError) { Connectors::Base.instance.accounts(nil) }
    assert_raises(NotImplementedError) { Connectors::Base.instance.positions(nil, nil) }
    assert_raises(NotImplementedError) { Connectors::Base.instance.authorizations }
  end

  test "a connector reports nothing rather than nil for what it cannot answer" do
    assert_nil Connectors::Base.instance.cash(nil, nil)
    assert_equal [], Connectors::Base.instance.exchanges
  end

end
