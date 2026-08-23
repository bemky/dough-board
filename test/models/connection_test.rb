require "test_helper"

class ConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "connector must be one Connectors knows" do
    assert Connection.new(connector: "snaptrade").valid?
    assert Connection.new(connector: "plaid").valid?
    connection = Connection.new(connector: "nope")
    assert_not connection.valid?
    assert_includes connection.errors[:connector], "is not included in the list"
  end

  test "active leaves out disabled connections" do
    live = Connection.create!(connector: "snaptrade", foreign_id: "a")
    Connection.create!(connector: "snaptrade", foreign_id: "b", disabled_at: Time.current)

    assert_equal [live], Connection.active.to_a
  end

  test "label falls back to the connector when the institution is unknown" do
    assert_equal "Robinhood - Connection-1",
      Connection.new(connector: "snaptrade", financial_institution: "Robinhood", name: "Connection-1").label
    assert_equal "Snaptrade", Connection.new(connector: "snaptrade").label
  end

  test "sync enqueues a job for this connection" do
    connection = Connection.create!(connector: "snaptrade", foreign_id: "a")

    assert_enqueued_with job: ConnectionJob do
      connection.sync
    end
  end

  test "deleting a connection keeps the accounts it synced" do
    connection = Connection.create!(connector: "snaptrade", foreign_id: "a")
    account = Account.create!(name: "Individual", connection: connection,
      foreign_id: "acct-1", positions_source: "connection")

    connection.destroy!
    assert_nil account.reload.connection_id
  end

  test "only a provider's own error code means someone has to sign in again" do
    connection = Connection.new(connector: "plaid")

    connection.last_error = "ITEM_LOGIN_REQUIRED: the login details of this item have changed"
    assert connection.needs_reauthorization?

    connection.last_error = "INSTITUTION_DOWN: down for maintenance"
    assert_not connection.needs_reauthorization?

    connection.last_error = nil
    assert_not connection.needs_reauthorization?
  end

  test "deleting a connection releases it at the provider too" do
    connection = Connection.create!(connector: "plaid", foreign_id: "item-1",
      credentials: {"access_token" => "access-1"})
    released = []

    Connectors::Plaid.singleton_class.define_method(:disconnect!) { |c| released << c; true }
    connection.destroy!

    assert_equal [connection], released
  ensure
    Connectors::Plaid.singleton_class.remove_method(:disconnect!)
  end

  test "a provider that can't release a connection doesn't hold the row hostage" do
    connection = Connection.create!(connector: "plaid", foreign_id: "item-1")

    Connectors::Plaid.singleton_class.define_method(:disconnect!) do |_c|
      raise Connectors::ConnectionError, "ITEM_NOT_FOUND"
    end

    assert_difference "Connection.count", -1 do
      connection.destroy!
    end
  ensure
    Connectors::Plaid.singleton_class.remove_method(:disconnect!)
  end

end
