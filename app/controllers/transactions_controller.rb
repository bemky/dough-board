class TransactionsController < ApplicationController
  
  def index
    @transactions = Transaction.order(executed_at: :desc)
    
    @portfolio = {}
    @transactions.each do |transaction|
      @portfolio[transaction.asset.symbol] ||= {quantity: 0, value: 0}
      if transaction.type == "buy"
        @portfolio[transaction.asset.symbol][:quantity] += transaction.adjusted_quantity
      else
        @portfolio[transaction.asset.symbol][:quantity] -= transaction.adjusted_quantity
      end
    end
    
    @portfolio.each do |sym, asset|
      asset[:value] = asset[:quantity] * Asset.find_by_symbol(sym).price
    end
  end
  
end
