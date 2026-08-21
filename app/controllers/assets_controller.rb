class AssetsController < ApplicationController

  # Holdings across every account: transactions folded into per-asset positions.
  def index
    @portfolio = Transaction.portfolio.sort_by{|h| -h[:value]}
  end

  # Fetches (or reuses a <24h-old cached) quote for one symbol. Called by the
  # portfolio/transactions pages' JS after they've rendered with cached-only
  # prices, so the page never blocks on Finnhub while loading.
  def quote
    asset = Asset.find_by(symbol: params[:symbol].to_s)
    render json: {symbol: params[:symbol], price: asset&.price}
  end

end
