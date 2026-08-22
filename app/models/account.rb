class Account < ApplicationRecord

  # Where this account's holdings come from — and so, who is allowed to write
  # its positions.
  POSITIONS_SOURCES = {
    "transactions" => "Derived from this account's transactions",
    "manual" => "Entered and maintained by hand",
    "connection" => "Synced from a connected institution"
  }.freeze

  # The sources a person can choose. An account belongs to "connection" by
  # virtue of a connector having created it, not by anyone picking it.
  SELECTABLE_POSITIONS_SOURCES = POSITIONS_SOURCES.except("connection").freeze

  belongs_to :connection, optional: true

  has_many :transactions
  has_many :positions, dependent: :delete_all

  validates :name, presence: true
  validates :positions_source, inclusion: {in: POSITIONS_SOURCES.keys}

  def label
    "#{institution_name} - #{name}"
  end

  # Whether DerivePositionsJob owns this account's positions. When it does, a
  # hand-edited position would be rewritten on the job's next run, so the UI
  # doesn't offer to edit one.
  def derives_positions?
    positions_source == "transactions"
  end

  def manual_positions?
    positions_source == "manual"
  end

  def synced_positions?
    positions_source == "connection"
  end

  def positions_source_description
    POSITIONS_SOURCES[positions_source]
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
