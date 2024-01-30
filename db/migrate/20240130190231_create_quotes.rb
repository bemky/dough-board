class CreateQuotes < ActiveRecord::Migration[7.1]
  def change
    create_table :quotes do |t|
      t.belongs_to :asset
      t.float :price, null: false
      t.timestamp :quoted_at, null: false
      t.timestamps
    end
  end
end
