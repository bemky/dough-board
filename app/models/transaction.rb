class Transaction < ApplicationRecord
  self.inheritance_column = nil

  attr_accessor :symbol

  validates :type, inclusion: {in: %w(buy sale)}

  # Folds a set of transactions into per-symbol holdings valued at the asset's
  # current price. Callable on any scope, so `Transaction.portfolio` gives the
  # global portfolio and `account.transactions.portfolio` gives one account's.
  # Returns [{symbol:, asset:, quantity:, price:, value:}, ...], richest first.
  def self.portfolio
    holdings = {}
    includes(:asset).each do |transaction|
      holding = holdings[transaction.asset.symbol] ||= {
        symbol: transaction.asset.symbol, asset: transaction.asset, quantity: 0, value: 0
      }
      if transaction.type == "buy"
        holding[:quantity] += transaction.adjusted_quantity
      else
        holding[:quantity] -= transaction.adjusted_quantity
      end
    end

    holdings.values.each do |holding|
      # asset.cached_price is nil when there's no <24h-old quote on hand yet
      # (delisted/unknown symbol, or one just not fetched recently) — such
      # holdings render as unvalued (0) until the page's JS fetches a fresh
      # price from AssetsController#quote.
      holding[:price] = holding[:asset].cached_price
      holding[:value] = holding[:quantity] * (holding[:price] || 0)
    end.filter{|h| h[:quantity] > 0}
  end
  
  belongs_to :asset
  belongs_to :account

  before_validation :create_asset
  before_save :set_adjusted_quantity
  after_create_commit :load_asset_splits

  # Value of this holding at the asset's current price (cached via
  # asset.current_quote), as opposed to `value` which is the value at execution.
  def current_value
    return unless asset&.price
    (adjusted_quantity || quantity) * asset.price
  end

  # Same as `current_value` but never hits Finnhub — used for the transactions
  # table's initial render, which is filled in with a fresh price by the
  # page's JS afterward.
  def cached_value
    return unless asset&.cached_price
    (adjusted_quantity || quantity) * asset.cached_price
  end

  def create_asset
    return if asset_id
    self.asset = Asset.find_or_create_by(symbol: symbol)
  end
  
  # Refresh the asset's splits off-request, then recompute this transaction's
  # (and its siblings') adjusted_quantity. Skipped while the scrape is still
  # fresh — importing hundreds of rows for one symbol shouldn't queue hundreds
  # of scrapes.
  def load_asset_splits
    return if asset.splits_updated_at && asset.splits_updated_at > 24.hours.ago
    LoadSplitsJob.perform_later(asset)
  end

  # Uses the splits already on hand rather than Asset#load_splits, so saving a
  # transaction never blocks on the scraper; LoadSplitsJob fills in anything
  # newly scraped afterward.
  def set_adjusted_quantity(force=false)
    return if self.adjusted_quantity && !force
    self.adjusted_quantity = quantity
    asset.splits.each do |split|
      next unless split.split_at > executed_at
      self.adjusted_quantity = self.adjusted_quantity * split.ratio
    end
  end
  
  def set_adjusted_quantity!(force=false)
    set_adjusted_quantity(force)
    save
  end
  
end
