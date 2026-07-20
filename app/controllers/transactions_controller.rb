class TransactionsController < ApplicationController
  
  def index
    @transactions = Transaction.order(executed_at: :desc)
    @portfolio = @transactions.portfolio
  end
      else
      end
    end
  end
  
end
