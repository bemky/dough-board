class Transaction < ApplicationRecord
  self.inheritance_column = nil

  attr_accessor :symbol

  validates :type, inclusion: {in: %w(buy sale)}
  
  belongs_to :asset
  belongs_to :account

  before_validation :create_asset
  before_save :set_adjusted_quantity
  
  # Value of this holding at the asset's current price (cached via
  # asset.current_quote), as opposed to `value` which is the value at execution.
  def current_value
    return unless asset&.price
    (adjusted_quantity || quantity) * asset.price
  end

  def create_asset
    return if asset_id
    self.asset = Asset.find_or_create_by(symbol: symbol)
  end
  
  def set_adjusted_quantity(force=false)
    return if self.adjusted_quantity && !force
    self.adjusted_quantity = quantity
    asset.load_splits.each do |split|
      next unless split.split_at > executed_at
      self.adjusted_quantity = self.adjusted_quantity * split.ratio
    end
  end
  
  def set_adjusted_quantity!(force=false)
    set_adjusted_quantity(force)
    save
  end
  
end
