class Quote < ApplicationRecord

  belongs_to :asset

  before_validation :fetch

  def fetch(force=false)
    return if price && !force
    price = Finnhub.quote(asset.quote_symbol)
    # Abort the callback chain (so a blank Quote is never persisted) when
    # Finnhub returns nothing — e.g. an unknown symbol or a rate-limited request.
    throw :abort if price.nil?
    self.price = price
    self.quoted_at = Time.now
    price
  end

  def fetch!
    self.price = nil
    save!
  end
end
