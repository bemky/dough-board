# Replaces the `assets.exchange` string — validated against a hardcoded
# %w(nyse nasdaq) — with a reference table. Two values is not enough the moment
# holdings arrive from a brokerage rather than being typed in by hand.
#
# Only the two rows the existing data refers to are created here; the table is
# filled properly from a connector's reference data, which knows every venue
# along with its MIC, suffix and trading hours. Their codes and names are the
# ones that reference data uses, so it updates these rows rather than adding a
# second copy of each.
class CreateExchanges < ActiveRecord::Migration[8.1]

  BACKFILL = [
    ["NYSE", "XNYS", "New York Stock Exchange"],
    ["NASDAQ", "XNAS", "NASDAQ"]
  ].freeze

  class MigrationExchange < ActiveRecord::Base
    self.table_name = "exchanges"
  end

  class MigrationAsset < ActiveRecord::Base
    self.table_name = "assets"
    self.inheritance_column = nil
  end

  def up
    create_table :exchanges do |t|
      t.string :code, null: false
      t.string :mic_code
      t.string :name, null: false
      t.string :suffix
      t.string :timezone
      t.string :start_time
      t.string :close_time
      t.timestamps
      t.index :code, unique: true
    end

    now = Time.current
    MigrationExchange.insert_all(BACKFILL.map { |code, mic_code, name|
      {code: code, mic_code: mic_code, name: name,
       timezone: "America/New_York", start_time: "09:30:00", close_time: "16:00:00",
       created_at: now, updated_at: now}
    })

    add_reference :assets, :exchange, foreign_key: true

    # The old column only ever held "nyse"/"nasdaq".
    MigrationExchange.where(code: BACKFILL.map(&:first)).each do |exchange|
      MigrationAsset.where(exchange: exchange.code.downcase).update_all(exchange_id: exchange.id)
    end

    remove_column :assets, :exchange
  end

  def down
    add_column :assets, :exchange, :string

    MigrationExchange.where(code: BACKFILL.map(&:first)).each do |exchange|
      MigrationAsset.where(exchange_id: exchange.id).update_all(exchange: exchange.code.downcase)
    end

    remove_reference :assets, :exchange, foreign_key: true
    drop_table :exchanges
  end
end
