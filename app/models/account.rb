class Account < ApplicationRecord
  has_many :transactions
  has_many :positions, dependent: :delete_all

  validates :name, presence: true

  def label
    "#{institution_name} - #{name}"
  end

  # Holdings not fed by a connector are derived from this account's own
  # transactions by DerivePositionsJob.
  def manual?
    true
  end

  # The newest snapshot's rows. Empty until something has derived or synced
  # positions for this account.
  def current_positions
    return positions.none unless positions_as_of
    positions.where(as_of: positions_as_of)
  end

  # This account's holdings, valued at current prices. Memoized because valuing
  # a portfolio can hit Finnhub for every asset.
  def portfolio
    @portfolio ||= current_positions.portfolio
  end

  def value
    portfolio.sum { |holding| holding[:value] }
  end
end
