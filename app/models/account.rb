class Account < ApplicationRecord

  # Where this account's holdings come from — and so, who is allowed to write
  # its positions.
  POSITIONS_SOURCES = {
    "transactions" => "Derived from this account's transactions",
    "manual" => "Entered and maintained by hand",
    "amortized" => "Calculated from a loan's terms",
    "connection" => "Synced from a connected institution"
  }.freeze

  # The kind of debt an amortized account owes, when its terms don't say.
  DEFAULT_DEBT_SYMBOL = "DEBT:HOME_LOAN".freeze

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
  validate :loan_terms_describe_a_loan, if: :amortized_positions?

  # The balance follows from the terms, so a change to them is a change to the
  # holding — recompute it now rather than leaving the account wrong until the
  # next scheduled run. Guarded on the columns that matter so the job's own
  # `positions_as_of` write doesn't queue another one.
  after_commit :amortize, if: -> {
    amortized_positions? && (saved_change_to_loan_terms? || saved_change_to_positions_source?)
  }

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

  # Whether AmortizeLoanJob owns this account's positions: one debt, its balance
  # worked out from what the loan was written on. Like the derived and synced
  # sources, it rewrites the whole snapshot, so a hand-edited position here
  # would be overwritten on the next run.
  def amortized_positions?
    positions_source == "amortized"
  end

  # The loan behind this account, or nil when the terms don't describe one yet.
  def amortization
    return nil unless amortized_positions?
    Amortization.from(loan_terms)
  end

  # Which debt asset the balance is owed against. The *kind* of debt, not this
  # account — so a mortgage kept here folds into the same portfolio line as one
  # synced from an institution.
  def debt_symbol
    symbol = loan_terms&.dig("debt_symbol").presence || DEFAULT_DEBT_SYMBOL
    Asset::DEBT_NAMES.key?(symbol) ? symbol : DEFAULT_DEBT_SYMBOL
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

  private def amortize
    AmortizeLoanJob.perform_later(self)
  end

  # Rejecting the terms rather than the account would leave an amortized account
  # reporting no balance at all, which reads as a loan that's been paid off.
  private def loan_terms_describe_a_loan
    return if Amortization.from(loan_terms)

    errors.add(:loan_terms, "need a principal, a rate under 100%, a term of " \
      "1-#{Amortization::MAX_TERM_MONTHS} months, and a start date")
  end
end
