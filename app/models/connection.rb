class Connection < ApplicationRecord

  has_many :accounts, dependent: :nullify

  validates :connector, inclusion: {in: -> (_) { Connectors.names }}

  scope :active, -> { where(disabled_at: nil) }

  # The connector object this connection talks through. Named to leave the
  # `connector` column holding the plain string it is.
  def client
    Connectors.for(connector)
  end

  def sync(as_of: nil)
    ConnectionJob.perform_later(self, as_of: as_of)
  end

  def disabled?
    disabled_at.present?
  end

  def label
    [financial_institution.presence || connector.titleize, name.presence].compact.join(" - ")
  end

  # Creates a Connection for every authorization a connector's credentials can
  # already see, and updates the ones on hand. For a SnapTrade Personal key the
  # connections are made on SnapTrade's own site, so this is how they arrive
  # here — there is no in-app connection portal to run.
  def self.discover!(connector)
    Connectors.for(connector).authorizations.map do |attributes|
      connection = find_or_initialize_by(connector: connector, foreign_id: attributes[:foreign_id])
      connection.update!(attributes.except(:foreign_id))
      connection
    end
  end

end
