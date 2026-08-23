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

  # Plaid is connected to in the browser rather than discovered, so these lean on
  # a stand-in connector: what's under test is the round trip through the
  # controller, not Plaid.
  class StubLinkConnector < Connectors::Base
    class << self
      attr_accessor :connect_attributes, :error
      attr_reader :link_token_for, :link_token_kind, :exchanged

      def discoverable? = false
      def linkable? = true
      def configured? = true

      def link_token(connection = nil, kind: LINK_KINDS.keys.first)
        raise Connectors::ConnectionError, error if error
        @link_token_for = connection
        @link_token_kind = kind
        "link-sandbox-token"
      end

      def connect!(public_token)
        raise Connectors::ConnectionError, error if error
        @exchanged = public_token
        connect_attributes
      end

      def reset!
        @connect_attributes = {foreign_id: "item-1", credentials: {"access_token" => "access-1"},
          financial_institution: "Wells Fargo", financial_institution_slug: "ins_1"}
        @error = @link_token_for = @link_token_kind = @exchanged = nil
      end
    end
  end

  # The other half of the pair: connected to on its own site, and so discovered
  # rather than linked.
  class StubDiscoverConnector < Connectors::Base
    def self.configured? = true
    def self.authorizations = []
  end

  def with_stub_connector
    original = Connectors::REGISTRY
    StubLinkConnector.reset!
    Connectors.send(:remove_const, :REGISTRY)
    Connectors.const_set(:REGISTRY, original.merge(
      "stub" => StubLinkConnector.name, "found" => StubDiscoverConnector.name
    ).freeze)
    yield
  ensure
    Connectors.send(:remove_const, :REGISTRY)
    Connectors.const_set(:REGISTRY, original)
  end

  test "the list offers Discover or Connect depending on what the connector supports" do
    with_stub_connector do
      get connections_path
      assert_response :success

      # One link per kind: an institution that does brokerages and one that does
      # credit cards are rarely the same institution.
      assert_select "a[href=?]", link_connections_path(connector: "stub", kind: "holdings"),
        text: "Connect Stub: bank or brokerage"
      assert_select "a[href=?]", link_connections_path(connector: "stub", kind: "debts"),
        text: "Connect Stub: card or loan"
      assert_select "button", text: "Discover Found"
      # Neither connector is offered the other's way of connecting.
      assert_select "button", text: "Discover Stub", count: 0
      assert_select "a[href^=?]", link_connections_path(connector: "found"), count: 0
    end
  end

  test "link renders the page that runs the provider's flow" do
    with_stub_connector do
      get link_connections_path(connector: "stub")
      assert_response :success
      assert_select "[data-plaid-link=?]", "link-sandbox-token"
      assert_nil StubLinkConnector.link_token_for
    end
  end

  test "link asks for the kind of institution the button named" do
    with_stub_connector do
      get link_connections_path(connector: "stub", kind: "debts")
      assert_response :success
      assert_equal "debts", StubLinkConnector.link_token_kind
      assert_select "h1", text: /card or loan/

      # An unknown kind falls back rather than asking the provider for nonsense.
      get link_connections_path(connector: "stub", kind: "houses")
      assert_equal "holdings", StubLinkConnector.link_token_kind
    end
  end

  test "link for an existing connection asks for a token that updates it in place" do
    with_stub_connector do
      connection = Connection.create!(connector: "stub", foreign_id: "item-1",
        financial_institution: "Wells Fargo")

      get link_connections_path(connection_id: connection.id)
      assert_response :success
      assert_equal connection, StubLinkConnector.link_token_for
    end
  end

  test "link says why rather than rendering a page that can't work" do
    with_stub_connector do
      StubLinkConnector.error = "Plaid credentials are missing"

      get link_connections_path(connector: "stub")
      assert_redirected_to connections_path
      assert_match "credentials are missing", flash[:alert]
    end
  end

  test "completing a link trades the token, creates the connection and syncs it" do
    with_stub_connector do
      assert_difference "Connection.count", 1 do
        assert_enqueued_with job: ConnectionJob do
          post complete_link_connections_path, params: {connector: "stub", public_token: "public-1"}
        end
      end

      assert_equal "public-1", StubLinkConnector.exchanged
      connection = Connection.find_by(connector: "stub", foreign_id: "item-1")
      assert_equal({"access_token" => "access-1"}, connection.credentials)
      assert_equal "Wells Fargo", connection.financial_institution
      assert_redirected_to connections_path
      assert_match "Connected Wells Fargo", flash[:notice]
    end
  end

  test "an update-mode run issues no token, and clears the error it was carrying" do
    with_stub_connector do
      connection = Connection.create!(connector: "stub", foreign_id: "item-1",
        credentials: {"access_token" => "access-1"},
        last_error: "ITEM_LOGIN_REQUIRED: sign in again", disabled_at: Time.current)

      assert_no_difference "Connection.count" do
        post complete_link_connections_path, params: {connection_id: connection.id, connector: "stub"}
      end

      connection.reload
      assert_nil connection.last_error
      assert_nil connection.disabled_at
      # Nothing was exchanged: the credentials already stored start working again.
      assert_nil StubLinkConnector.exchanged
    end
  end

  test "relinking an institution already here updates it rather than colliding" do
    with_stub_connector do
      existing = Connection.create!(connector: "stub", foreign_id: "item-1",
        last_error: "ITEM_LOGIN_REQUIRED: sign in again")

      assert_no_difference "Connection.count" do
        post complete_link_connections_path, params: {connector: "stub", public_token: "public-1"}
      end

      assert_nil existing.reload.last_error
      assert_equal({"access_token" => "access-1"}, existing.credentials)
    end
  end

  test "a failed exchange says so instead of leaving a half-made connection" do
    with_stub_connector do
      StubLinkConnector.error = "INVALID_PUBLIC_TOKEN: could not find matching token"

      assert_no_difference "Connection.count" do
        post complete_link_connections_path, params: {connector: "stub", public_token: "nope"}
      end

      assert_redirected_to connections_path
      assert_match "INVALID_PUBLIC_TOKEN", flash[:alert]
    end
  end

  test "a connection that needs signing in to again offers Reconnect" do
    with_stub_connector do
      connection = Connection.create!(connector: "stub", foreign_id: "item-1",
        financial_institution: "Wells Fargo",
        last_error: "ITEM_LOGIN_REQUIRED: the login details of this item have changed")

      get connections_path
      assert_response :success
      assert_select "a[href=?]", link_connections_path(connection_id: connection.id), text: "Reconnect"
    end
  end

  test "an ordinary failure is not a reason to sign in again" do
    with_stub_connector do
      Connection.create!(connector: "stub", foreign_id: "item-1",
        last_error: "INSTITUTION_DOWN: the institution is down for maintenance")

      get connections_path
      assert_response :success
      assert_select "a", text: "Reconnect", count: 0
    end
  end

  test "an empty list explains where connections come from" do
    Connection.delete_all

    get connections_path
    assert_response :success
    assert_select "p", text: /No connections yet/
  end
end
