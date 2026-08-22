require "test_helper"

class ConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "connector must be one Connectors knows" do
    assert Connection.new(connector: "snaptrade").valid?
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

end
