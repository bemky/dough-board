class Position < ApplicationRecord

  belongs_to :account
  belongs_to :asset

  # Lets a position be entered by ticker rather than by asset id, the same way
  # a transaction can be.
  attr_accessor :symbol

  validates :units, presence: true
  validates :as_of, presence: true

  before_validation :create_asset
  before_validation :set_as_of
  before_save :set_value

  # An account with no snapshot yet has nowhere to show this position, so the
  # first one entered by hand establishes one.
  after_create :adopt_snapshot, unless: -> { account.positions_as_of }

  # The newest snapshot for every account, across all of them. Accounts record
  # the timestamp their latest run wrote, so this is an equality join rather
  # than a per-group maximum.
  scope :current, -> { joins(:account).where("positions.as_of = accounts.positions_as_of") }

  # Folds a set of positions into per-asset holdings. Callable on any scope, so
  # `Position.current.portfolio` gives the whole portfolio and
  # `account.current_positions.portfolio` gives one account's.
  # Returns [{symbol:, asset:, units:, price:, value:}, ...], unsorted.
  #
  # A holding can be negative: a debt is units of dollars owed rather than held
  # (see Asset#liability?), and the sum of the whole set is a net worth.
  def self.portfolio
    holdings = {}
    includes(:asset).each do |position|
      holding = holdings[position.asset_id] ||= {
        symbol: position.asset.symbol, asset: position.asset, units: 0, value: 0,
        price: nil, quoted_price: nil
      }
      holding[:units] += position.units
      # Kept only as a fallback for assets Finnhub has no quote for; a holding
      # spread over two accounts can carry two different broker prices, so the
      # larger position wins.
      if position.price && (holding[:quoted_price].nil? || position.units > holding[:quoted_price].first)
        holding[:quoted_price] = [position.units, position.price]
      end
    end

    holdings.values.each do |holding|
      # asset.cached_price is nil when there's no <24h-old quote on hand (a
      # delisted or unknown symbol, or one simply not fetched recently). Prefer
      # it over the broker's price so the value shown matches what the page's
      # JS recomputes when it refreshes quotes from AssetsController#quote.
      holding[:price] = holding[:asset].cached_price || holding[:quoted_price]&.last
      holding[:value] = holding[:units] * (holding[:price] || 0)
      holding.delete(:quoted_price)
      # A holding sold down to nothing, or a debt paid off, is not a holding.
    end.filter { |holding| !holding[:units].to_f.zero? }
  end

  def current_value
    return unless price
    units * price
  end

  # Whether this row can be edited by hand, or belongs to whatever writes the
  # account's positions.
  def editable?
    account.manual_positions?
  end

  private def create_asset
    return if asset_id || symbol.blank?
    self.asset = Asset.find_or_create_by(symbol: symbol)
  end

  private def set_as_of
    self.as_of ||= account&.positions_as_of || Time.current
  end

  private def adopt_snapshot
    account.update!(positions_as_of: as_of)
  end

  private def set_value
    self.value = price ? units * price : nil
    self.cost_basis = average_price ? units * average_price : nil
  end

end
