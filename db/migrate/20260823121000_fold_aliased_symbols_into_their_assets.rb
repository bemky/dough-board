# Connectors now hand back one name for one instrument
# (Connectors::Base::SYMBOL_ALIASES), but everything synced before that is still
# filed under whatever its venue called it — a Kraken XXBT sitting beside a
# Coinbase BTC as two assets, two tiles, two cost bases, and no quote on the
# Kraken half. Fold each one onto the asset it was always the same thing as.
#
# The map below is a copy rather than a reference to the constant. A migration
# is a record of what ran on a given day; symbols added to the connectors' map
# later cover new syncs on their own and bring a migration of their own for
# whatever is already on hand.
class FoldAliasedSymbolsIntoTheirAssets < ActiveRecord::Migration[8.1]

  ALIASES = {
    "XBT" => "BTC",
    "XXBT" => "BTC",
    "XDG" => "DOGE",
    "XXDG" => "DOGE",
    "XETC" => "ETC",
    "XETH" => "ETH",
    "XLTC" => "LTC",
    "XMLN" => "MLN",
    "XREP" => "REP",
    "XXLM" => "XLM",
    "XXMR" => "XMR",
    "XXRP" => "XRP",
    "XZEC" => "ZEC",
    "ZAUD" => "AUD",
    "ZCAD" => "CAD",
    "ZEUR" => "EUR",
    "ZGBP" => "GBP",
    "ZJPY" => "JPY",
    "ZUSD" => "USD"
  }.freeze

  # Attributes worth keeping from the asset being folded away, where the one
  # being kept never learned them.
  BACKFILLED = %w(name type figi_code exchange_id).freeze

  class MigrationAsset < ActiveRecord::Base
    self.table_name = "assets"
    self.inheritance_column = nil
  end

  class MigrationPosition < ActiveRecord::Base
    self.table_name = "positions"
  end

  def up
    ALIASES.each do |venue_symbol, canonical_symbol|
      asset = MigrationAsset.find_by(symbol: venue_symbol)
      next unless asset

      # Quotes and splits were fetched against a symbol that named the wrong
      # thing — Finnhub can't price XXBT at all — so they go rather than come
      # along. Asset#current_quote refetches on the next read, and LoadSplitsJob
      # rescrapes once splits_updated_at is clear.
      execute "DELETE FROM quotes WHERE asset_id = #{asset.id}"
      execute "DELETE FROM splits WHERE asset_id = #{asset.id}"

      keeper = MigrationAsset.find_by(symbol: canonical_symbol)
      unless keeper
        # Nothing to merge with: the asset is right, only its name was wrong.
        asset.update_columns(symbol: canonical_symbol, splits_updated_at: nil)
        next
      end

      backfill(keeper, asset)
      merge_positions(asset, keeper)
      execute "UPDATE transactions SET asset_id = #{keeper.id} WHERE asset_id = #{asset.id}"
      asset.delete
    end
  end

  # Deliberately empty. Which holdings arrived under which spelling is exactly
  # what the merge discards, and the connectors would fold them together again
  # on the next sync anyway.
  def down
  end

  private

  def backfill(keeper, asset)
    attributes = BACKFILLED.filter_map do |column|
      value = asset[column]
      [column, value] if keeper[column].blank? && value.present?
    end.to_h
    keeper.update_columns(attributes) if attributes.any?
  end

  # (account, asset, as_of) is unique, so an account that held both spellings in
  # one snapshot can't just have its rows repointed: the two rows are one
  # holding and have to be added together, the way ConnectionJob#combine folds a
  # position reported per wallet. Weighting the average price by units keeps the
  # cost basis describing the whole thing.
  def merge_positions(asset, keeper)
    MigrationPosition.where(asset_id: asset.id).find_each do |position|
      existing = MigrationPosition.find_by(
        account_id: position.account_id, asset_id: keeper.id, as_of: position.as_of
      )
      unless existing
        position.update_columns(asset_id: keeper.id)
        next
      end

      units = existing.units + position.units
      # Only the rows that reported a cost can weight it, so they carry their
      # own denominator.
      priced = [existing, position].select(&:average_price)
      priced_units = priced.sum(&:units)
      average_price =
        if priced_units.nonzero?
          priced.sum { |row| row.units * row.average_price } / priced_units
        end
      price = existing.price || position.price

      existing.update_columns(
        units: units,
        price: price,
        average_price: average_price,
        cost_basis: average_price && units * average_price,
        value: price && units * price
      )
      position.delete
    end
  end
end
