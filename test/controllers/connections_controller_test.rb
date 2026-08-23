require "test_helper"

class ConnectionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in
    @connection = Connection.create!(connector: "snaptrade", foreign_id: "auth-1",
      name: "Connection-1", financial_institution: "Robinhood",
      synced_at: 2.hours.ago)
  end

  test "index lists connections with their accounts and last sync" do
    Account.create!(name: "Individual", institution_name: "Robinhood",
      connection: @connection, foreign_id: "acct-1", positions_source: "connection")

    get connections_path
    assert_response :success
    assert_select "td", text: /Robinhood/
    assert_select "td", text: /about 2 hours ago/
  end

  test "index says when a connection has never synced" do
    @connection.update!(synced_at: nil)

    get connections_path
    assert_response :success
    assert_select "span", text: "Never"
  end

  test "index surfaces the last error" do
    @connection.update!(last_error: "Brokerage is unreachable")

    get connections_path
    assert_response :success
    assert_select "span[data-tooltip=?]", "Brokerage is unreachable"
  end

  test "sync enqueues a job and returns to the list" do
    assert_enqueued_with job: ConnectionJob do
      post sync_connection_path(@connection)
    end
    assert_redirected_to connections_path
    assert_match "Syncing", flash[:notice]
  end

  test "destroy removes the connection but keeps its accounts" do
    account = Account.create!(name: "Individual", institution_name: "Robinhood",
      connection: @connection, foreign_id: "acct-1", positions_source: "connection")

    assert_difference "Connection.count", -1 do
      delete connection_path(@connection)
    end
    # The holdings already synced are still worth keeping.
    assert_nil account.reload.connection_id
  end

  test "discover rejects an unknown connector" do
    post discover_connections_path(connector: "nope")
    assert_redirected_to connections_path
    assert_match "Unknown connector", flash[:alert]
  end

  test "an empty list explains where connections come from" do
    Connection.delete_all

    get connections_path
    assert_response :success
    assert_select "p", text: /No connections yet/
  end
end
