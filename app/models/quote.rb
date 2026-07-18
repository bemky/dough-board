class Quote < ApplicationRecord
  
  belongs_to :asset
  
  before_validation :fetch
  
  def fetch
    return if price
    if asset.type == "crypto"
      data = AlphaVantage.exchange(asset.symbol)
      self.price = data["Exchange Rate"]
    else
      data = AlphaVantage.quote(asset.symbol)
      self.price = data["price"]
    end
    self.quoted_at = Time.now
  end
end
