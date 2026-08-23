class Transaction < ApplicationRecord
  self.inheritance_column = nil

  attr_accessor :symbol

  # The activity types a brokerage can report, lowercased. buy and sale keep the
  # names Dough Board has always used (SnapTrade calls them BUY and SELL), so
  # existing rows and the CSV importer's side mapping stay valid.
  TYPES = %w(
    buy sale dividend substitute_dividend stock_dividend rei
    contribution withdrawal interest fee tax
    optionexpiration optionassignment optionexercise
    transfer external_asset_transfer_in external_asset_transfer_out
    split adjustment
  ).freeze

  # How each type moves the share count, for the fold in DerivePositionsJob. A
  # type absent from this table does not move units at all — a dividend or a fee
  # is cash, not shares, and the old "buy adds, everything else subtracts" fold
  # would have subtracted it.
  UNIT_SIGNS = {
    "buy" => 1,
    "rei" => 1,
    "stock_dividend" => 1,
    "external_asset_transfer_in" => 1,
    "optionexercise" => 1,
    "adjustment" => 1,
    # Reported in both directions under the one type, with the direction carried
    # by the sign of `units` — so take it as given rather than forcing one.
    "transfer" => 1,
    "sale" => -1,
    "external_asset_transfer_out" => -1,
    "optionassignment" => -1
  }.freeze

  validates :type, inclusion: {in: TYPES}

  belongs_to :asset
  belongs_to :account

  before_validation :create_asset
  before_save :set_adjusted_quantity
  after_create_commit :load_asset_splits

  # Positions are what the portfolio reads, so a hand-entered or edited
  # transaction has to be folded back into them. Correcting an account's current
  # snapshot rather than appending a new one keeps an import of hundreds of rows
  # from writing hundreds of points into the history.
  after_commit :derive_account_positions, on: [:create, :update, :destroy]

  # How many units this transaction moves, signed. nil for the types that move
  # cash rather than shares.
  def units
    sign = UNIT_SIGNS[type]
    return unless sign
    quantity = adjusted_quantity || self.quantity
    quantity && sign * quantity
  end

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

  # DerivePositionsJob folds an entire account in one go, so a bulk import wants
  # one run at the end rather than one per row. Callers that use this are
  # responsible for enqueuing that run themselves.
  def self.without_position_derivation
    previous = Thread.current[:skip_position_derivation]
    Thread.current[:skip_position_derivation] = true
    yield
  ensure
    Thread.current[:skip_position_derivation] = previous
  end

  def derive_account_positions
    return if Thread.current[:skip_position_derivation]
    return unless account&.derives_positions?
    DerivePositionsJob.perform_later(account)
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
