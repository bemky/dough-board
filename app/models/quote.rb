class Quote < ApplicationRecord
  
  belongs_to :asset
  
  before_validation :fetch
  
  def fetch(force=false)
    return if price && !force
    if asset.type == "crypto"
      data = AlphaVantage.exchange(asset.symbol)
      price = data["Exchange Rate"]
    else
      data = AlphaVantage.quote(asset.symbol)
      price = data["price"]
    end
    quoted_at = Time.now
    price
  end
  
  def fetch!
    update!(price: fetch(true), quoted_at: Time.now)
  end
end
