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

  def sync
    resource.sync
    redirect_to connections_path, notice: "Syncing #{resource.label}."
  end

end
