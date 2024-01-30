class Transaction < ApplicationRecord
  self.inheritance_column = nil

  attr_accessor :symbol

  validates :type, inclusion: {in: %w(buy sale)}
  
  belongs_to :asset
  
  before_validation :create_asset
  
  def create_asset
    return if asset_id
    self.asset = Asset.find_or_create_by(symbol: symbol)
  end
  
end
