class Asset < ApplicationRecord
  self.inheritance_column = nil

  has_many :transactions
  has_many :quotes, -> { order(quoted_at: :desc)}, dependent: :destroy
  
  normalizes :symbol, with: -> symbol { symbol.upcase }

  validates :type, inclusion: {in: %w(stock fund crypto), allow_nil: true}
  validates :exchange, inclusion: {in: %w(nyse nasdaq), allow_nil: true}
  
  def price
    current_quote&.price
  end
  
  def current_quote
    quotes.filter(quoted_at: {gt: 24.hours.ago}).order(quoted_at: :desc).first ||
    Quote.create(asset: self)
  end
end