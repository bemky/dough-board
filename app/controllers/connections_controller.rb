class ConnectionsController < ApplicationController

  def index
    @connections = Connection.includes(:accounts).sort(orders)
  end

  private def default_orders
    {financial_institution: :asc}
  end

  # standardapi provides show/new/create/update but no edit action, so define
  # one that populates the resource ivar for edit.html.erb's form.
  def edit
    instance_variable_set("@#{model.model_name.singular}", resource)
  end

  # Picks up connections made on the provider's own site. A SnapTrade Personal
  # key has no in-app connection portal, so this is how a new brokerage arrives.
  def discover
    connections = Connection.discover!(params[:connector])
    redirect_to connections_path, notice: "Found #{connections.length} connection#{"s" unless connections.length == 1}."
  rescue Connectors::ConnectionError, ArgumentError => e
    redirect_to connections_path, alert: e.message
  end

  # Renders the page that runs the provider's browser flow. With a
  # connection_id it opens in update mode instead, which is how an institution
  # that has expired its consent gets signed into again.
  def link
    @connector = params[:connector].presence
    @connection = Connection.find(params[:connection_id]) if params[:connection_id].present?
    @connector ||= @connection&.connector
    # Which side of the balance sheet is being connected. Ignored in update
    # mode, where the Item already knows what it was linked for.
    @kind = Connectors::Base::LINK_KINDS.key?(params[:kind]) ? params[:kind] : Connectors::Base::LINK_KINDS.keys.first
    @link_token = Connectors.for(@connector).link_token(@connection, kind: @kind)
  rescue Connectors::ConnectionError, ArgumentError => e
    redirect_to connections_path, alert: e.message
  end

  # Where the flow comes back to. A new connection arrives as a one-time
  # public_token to trade in; an update-mode run issues none, because the
  # credentials already stored start working again the moment the account holder
  # is through.
  def complete_link
    connection =
      if params[:public_token].present?
        Connection.link!(params[:connector], params[:public_token])
      else
        Connection.find(params[:connection_id]).tap do |existing|
          existing.update!(disabled_at: nil, last_error: nil)
        end
      end

    connection.sync
    redirect_to connections_path, notice: "Connected #{connection.label}. Syncing now."
  rescue Connectors::ConnectionError, ArgumentError, ActiveRecord::RecordInvalid,
    ActiveRecord::RecordNotFound => e
    redirect_to connections_path, alert: e.message
  end

  def sync
    resource.sync
    redirect_to connections_path, notice: "Syncing #{resource.label}."
  end

end
