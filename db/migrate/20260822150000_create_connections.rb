# A read-only link to one financial institution, brokered by a connector.
#
# For SnapTrade a connection is one brokerage authorization; the credentials
# that reach it are app-level (config/credentials.yml), so `credentials` here
# stays empty. It exists for connectors whose secrets really are per-connection
# — Plaid issues an access token per item — so adding one doesn't need a
# migration.
class CreateConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :connections do |t|
      t.string :connector, null: false
      t.string :foreign_id
      t.string :name
      t.string :financial_institution
      t.string :financial_institution_slug
      t.json :credentials
      t.datetime :synced_at
      t.datetime :disabled_at
      t.string :last_error
      t.timestamps
      t.index [:connector, :foreign_id], unique: true
    end

    add_reference :accounts, :connection, foreign_key: true
    add_column :accounts, :foreign_id, :string
    add_index :accounts, [:connection_id, :foreign_id], unique: true, where: "foreign_id IS NOT NULL"
  end
end
