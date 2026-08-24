class Quote < ApplicationRecord

  belongs_to :asset

  before_validation :fetch

  def fetch(force=false)
    return if price && !force
    # Dollars held or owed are worth their face value — no source has anything
    # to say about either.
    throw :abort if asset.face_value?
    # Which source answers is the asset's business (see app/lib/valuators): a
    # security goes to Finnhub, a house to its listing page, a car to a
    # depreciation curve.
    price = asset.valuator.price(asset)
    # Abort the callback chain (so a blank Quote is never persisted) when the
    # source returns nothing — an unknown symbol, a rate-limited request, a
    # listing that no longer parses.
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
