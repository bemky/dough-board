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

  # Both delete_all rather than destroy_all: a transaction's callbacks exist to
  # keep this account's positions in sync, and the account is going away. Running
  # them per row would enqueue a DerivePositionsJob for every transaction and
  # then delete the account they were queued for.
  has_many :transactions, dependent: :delete_all
  has_many :positions, dependent: :delete_all

  validates :name, presence: true
  validates :positions_source, inclusion: {in: POSITIONS_SOURCES.keys}

  def label
    "#{institution_name} - #{name}"
  end

  # Takes the institution's own name for this account, but only as far as it is
  # still ours to take. `foreign_name` records what they last reported: while it
  # matches `name`, nobody has typed a name of their own and a rename on their
  # side is worth carrying across; once the two differ, the local name is a
  # deliberate override and a sync leaves it alone.
  def name_from_institution(institution_name)
    self.name = institution_name if institution_name.present? && !renamed?
    self.foreign_name = institution_name
  end

  # Whether someone has given this account a name of its own.
  def renamed?
    name.present? && foreign_name.present? && name != foreign_name
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
