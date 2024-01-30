class Quote < ApplicationRecord
  
  belongs_to :asset
  
  before_validation :fetch
  
  def fetch
    return if price
    data = AlphaVantage.quote(asset.symbol)
    self.price = data["price"]
    self.quoted_at = Time.now
  end
end
