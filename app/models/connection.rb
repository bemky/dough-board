class Connection < ApplicationRecord

  has_many :accounts, dependent: :nullify

  validates :connector, inclusion: {in: -> (_) { Connectors.names }}

  scope :active, -> { where(disabled_at: nil) }

  # Plaid counts Items against the plan, so a connection deleted here has to be
  # released there too or the slot stays spent. before_destroy rather than
  # after: if the provider refuses in a way worth knowing about, the row is
  # still here to try again. Connectors that have nothing to release say so by
  # returning false from #disconnect!.
  before_destroy :release_remote_connection

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

  # The other way a connection arrives: the provider's browser flow (Plaid Link)
  # hands back a one-time token, and the connector trades it for the credentials
  # this connection will use from then on. Matched on foreign_id so relinking an
  # institution already here updates it — Plaid reuses an Item's id — rather
  # than colliding with the unique index on (connector, foreign_id).
  def self.link!(connector, public_token)
    attributes = Connectors.for(connector).connect!(public_token)
    connection = find_or_initialize_by(connector: connector, foreign_id: attributes[:foreign_id])
    # A relink is what fixes an expired connection, so the error it was carrying
    # is no longer true.
    connection.assign_attributes(attributes.except(:foreign_id).compact)
    connection.disabled_at = nil
    connection.last_error = nil
    connection.save!
    connection
  end

  # Whether the last sync failed in a way only the account holder can fix, by
  # signing in to the institution again through the provider's flow. Plaid says
  # so precisely; a connector that doesn't report a code never claims it.
  REAUTHORIZATION_ERRORS = %w[ITEM_LOGIN_REQUIRED PENDING_EXPIRATION].freeze

  def needs_reauthorization?
    REAUTHORIZATION_ERRORS.any? { |code| last_error.to_s.start_with?(code) }
  end

  def linkable?
    client.linkable?
  end

  private def release_remote_connection
    client.disconnect!(self)
  rescue Connectors::ConnectionError, ArgumentError => e
    # Nothing here is worth blocking the delete over — the row going away is
    # what was asked for, and a stranded Item is a smaller problem than a
    # connection that can't be removed.
    Rails.logger.warn("Connection##{id} disconnect failed: #{e.message}")
    true
  end

end
