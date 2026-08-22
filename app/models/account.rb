class Account < ApplicationRecord
  has_many :transactions

  validates :name, presence: true

  def label
    "#{institution_name} - #{name}"
  end

  # This account's holdings, valued at current prices. Memoized because valuing
  # a portfolio can hit Finnhub for every asset.
  def portfolio
    @portfolio ||= transactions.portfolio
  end

  def value
    portfolio.sum { |holding| holding[:value] }
  end
end
