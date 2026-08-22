# A holding, as of a moment in time. Every row written by one derivation or sync
# run shares that run's `as_of`, and the account records the newest one in
# `positions_as_of` — that pair is what makes "the current snapshot" a plain
# equality check rather than a window function SQLite would have to emulate.
class CreatePositions < ActiveRecord::Migration[8.1]
  def change
    create_table :positions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :asset, null: false, foreign_key: true
      t.datetime :as_of, null: false
      t.float :units, null: false
      t.float :price
      t.float :value
      t.float :average_price
      t.float :cost_basis
      t.float :open_pnl
      t.string :currency, null: false, default: "USD"
      t.timestamps
      t.index [:account_id, :asset_id, :as_of], unique: true
      t.index [:asset_id, :as_of]
    end

    add_column :accounts, :positions_as_of, :datetime

    # SnapTrade's stable instrument identifier. Symbols get reused and renamed;
    # FIGI codes do not.
    add_column :assets, :figi_code, :string
  end
end
