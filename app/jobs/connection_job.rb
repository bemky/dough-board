# Pulls one connection's accounts, positions and activities through its
# connector and writes them down.
#
# Positions come from the institution, which knows about corporate actions,
# transfers and reinvestments we would never reconstruct correctly from
# transactions — so a synced account's positions are taken as given, and
# DerivePositionsJob leaves it alone (Account#derives_positions? is false for
# positions_source "connection").
class ConnectionJob < ApplicationJob
  queue_as :default

  # Skipped when the connection no longer exists (deleted between enqueue and run).
  discard_on ActiveJob::DeserializationError

  # With no `as_of` this corrects the current snapshot in place, the same way
  # DerivePositionsJob does; the periodic rake task passes one to append a point
  # to the value history.
  def perform(connection, as_of: nil)
    connector = connection.client

    connector.accounts(connection).each do |attributes|
      account = upsert_account(connection, attributes)
      sync_positions(connector, connection, account, as_of)
      sync_transactions(connector, connection, account)
    end

    connection.update!(synced_at: Time.current, last_error: nil)
  rescue Connectors::ConnectionError, ActiveRecord::RecordInvalid => e
    # Worth keeping on the connection so the UI can say why it's stale, and
    # worth re-raising so the queue records a failure rather than a quiet no-op.
    connection.update_columns(last_error: e.message.to_s.truncate(250), updated_at: Time.current)
    raise
  end

  private

  def upsert_account(connection, attributes)
    account = Account.find_or_initialize_by(connection: connection, foreign_id: attributes[:foreign_id])
    account.assign_attributes(attributes.except(:foreign_id))
    # An account a connector created is one a connector maintains.
    account.positions_source = "connection"
    account.name = account.foreign_id if account.name.blank?
    account.save!
    account
  end

  def sync_positions(connector, connection, account, as_of)
    as_of ||= account.positions_as_of || Time.current
    rows = connector.positions(connection, account)

    cash = connector.cash(connection, account)

    asset_ids = combine(rows).map do |row|
      position = Position.find_or_initialize_by(
        account_id: account.id, asset_id: asset_for(row).id, as_of: as_of
      )
      position.units = row[:units]
      position.price = row[:price]
      position.average_price = row[:average_price]
      position.currency = row[:currency] || "USD"
      position.save!
      position.asset_id
    end

    asset_ids << cash_position(account, cash, as_of).asset_id if cash&.nonzero?

    # Anything the institution no longer reports.
    Position.where(account_id: account.id, as_of: as_of).where.not(asset_id: asset_ids).delete_all

    account.update!(positions_as_of: as_of)
  end

  # One holding can arrive as several rows: Coinbase reports a position per
  # wallet, so an account holding coins in a vault and in its default wallet
  # sends two BTC rows. A Position is unique on (account, asset, as_of), so
  # writing them one by one silently kept only the last — the vault's balance
  # disappeared. Fold them into one holding instead, weighting the average
  # price by units so the cost basis still describes the whole thing.
  def combine(rows)
    rows.group_by { |row| row[:symbol] }.map do |_symbol, group|
      next group.first if group.one?

      units = group.sum { |row| row[:units].to_d }
      # Only the rows that reported a cost can weight it, so they carry their
      # own denominator.
      priced = group.select { |row| row[:average_price] }
      priced_units = priced.sum { |row| row[:units].to_d }
      average_price =
        if priced_units.nonzero?
          priced.sum { |row| row[:units].to_d * row[:average_price].to_d } / priced_units
        end

      group.max_by { |row| row[:units].to_d }.merge(
        units: units, average_price: average_price
      )
    end
  end

  # Uninvested cash rides along as a position against a cash asset, so it shows
  # up in the treemap and the account total without anything special-casing it —
  # and, unlike a column on the account, it belongs to one snapshot, so a
  # historical valuation reports the cash of its own moment.
  def cash_position(account, cash, as_of)
    asset = Asset.find_or_create_by!(symbol: "USD") { |a| a.type = "cash"; a.name = "US Dollar" }
    position = Position.find_or_initialize_by(account_id: account.id, asset_id: asset.id, as_of: as_of)
    position.units = cash
    position.price = 1.0
    position.save!
    position
  end

  def asset_for(row)
    asset = Asset.find_or_create_by!(symbol: row[:symbol])
    attributes = {
      name: asset.name.presence || row[:name],
      type: asset.type.presence || row[:type],
      figi_code: asset.figi_code.presence || row[:figi_code],
      exchange: asset.exchange || exchange_for(row[:exchange_mic])
    }.compact
    asset.update!(attributes) if attributes.any? { |key, value| asset.public_send(key) != value }
    asset
  end

  # Positions carry a MIC ("XNAS"), not the short code the seed list is keyed by.
  def exchange_for(mic_code)
    return if mic_code.blank?
    Exchange.find_by(mic_code: mic_code) || Exchange.find_by(code: mic_code)
  end

  def sync_transactions(connector, connection, account)
    connector.transactions(connection, account, since: connection.synced_at).each do |row|
      transaction = Transaction.find_or_initialize_by(account_id: account.id, foreign_id: row[:foreign_id])
      transaction.assign_attributes(row.except(:foreign_id))
      # A cash movement has no instrument behind it; park it against the cash
      # asset so transaction.asset is always something.
      transaction.symbol = "USD" if transaction.symbol.blank? && transaction.asset_id.nil?
      transaction.save!
    end
  end
end
