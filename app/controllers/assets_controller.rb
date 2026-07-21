class AssetsController < ApplicationController

  # Holdings across every account: transactions folded into per-asset positions.
  def index
    @portfolio = Transaction.portfolio
  end

end
