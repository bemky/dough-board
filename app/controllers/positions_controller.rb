class PositionsController < ApplicationController

  # Nested under /accounts/:account_id/positions this renders one account's
  # current holdings (the account subnav's Positions tab); unnested it renders
  # every account's, alongside the add form.
  def index
    @account = Account.find(params[:account_id]) if params[:account_id]
    scope = @account ? @account.current_positions : Position.current

    # `orders` sanitizes params[:order] against PositionACL#orders, so an
    # unpermitted sort key raises rather than reaching the query.
    @positions = scope.includes(:asset, :account).sort(orders)
  end

  # Largest holding first until a header is clicked. Private so it isn't routable.
  private def default_orders
    {value: :desc}
  end

  # standardapi provides show/new/create/update but no edit action, so define
  # one that populates the resource ivar for edit.html.erb's form.
  def edit
    instance_variable_set("@#{model.model_name.singular}", resource)
  end

end
