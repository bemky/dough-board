# Asset.find_or_create_by(symbol:) is the only way assets get created, and it's
# about to be called from background jobs as well as from Transaction#create_asset
# — concurrent callers can each miss the find and both create. Make the database
# say no.
class AddUniqueIndexToAssetSymbols < ActiveRecord::Migration[8.1]

  class MigrationAsset < ActiveRecord::Base
    self.table_name = "assets"
    self.inheritance_column = nil
  end

  def up
    # Fold any pre-existing duplicates onto the oldest row so the index can be
    # built. Nothing should have produced these, but a deploy shouldn't be the
    # thing that finds out.
    MigrationAsset.group(:symbol).having("count(*) > 1").pluck(:symbol).each do |symbol|
      keeper, *duplicates = MigrationAsset.where(symbol: symbol).order(:id).pluck(:id)
      %w(transactions quotes splits).each do |table|
        execute <<~SQL
          UPDATE #{table} SET asset_id = #{keeper} WHERE asset_id IN (#{duplicates.join(",")})
        SQL
      end
      MigrationAsset.where(id: duplicates).delete_all
    end

    add_index :assets, :symbol, unique: true
  end

  def down
    remove_index :assets, :symbol
  end
end
