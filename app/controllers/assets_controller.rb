class AssetsController < ApplicationController

  # Holdings across every account: each account's newest position snapshot,
  # summed per asset.
  def index
    @portfolio = Position.current.portfolio.sort_by{|h| -h[:value]}
  end

  # Assets are normally created for you — by a transaction's symbol, or by a
  # sync. A house or a car has neither, so it gets typed in here.
  def new
    @asset = Asset.new(type: params[:type])
  end

  # standardapi provides update but no edit action, so define one that populates
  # the resource ivar for edit.html.erb's form (same shape as TransactionsController).
  def edit
    instance_variable_set("@#{model.model_name.singular}", resource)
  end

  # standardapi's update redirects HTML requests to #show, which assets have no
  # route or view for — send the user back to the portfolio instead. JSON keeps
  # standardapi's behavior.
  def update
    instance_variable_set("@#{model.model_name.singular}", resource)

    if resource.update(model_params)
      headers['Affected-Rows'] = 1
      request.format == :html ? redirect_to(assets_path) : render(:show, status: :ok)
    else
      headers['Affected-Rows'] = 0
      request.format == :html ? render(:edit, status: :bad_request) : render(:show, status: :bad_request)
    end
  end

  # Fetches (or reuses a <24h-old cached) quote for one symbol. Called by the
  # portfolio/transactions pages' JS after they've rendered with cached-only
  # prices, so the page never blocks on Finnhub while loading.
  def quote
    asset = Asset.find_by(symbol: params[:symbol].to_s)
    render json: {symbol: params[:symbol], price: asset&.price}
  end

end
