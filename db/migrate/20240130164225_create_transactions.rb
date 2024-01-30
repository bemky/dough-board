class CreateTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :transactions do |t|
      t.belongs_to :asset, null: false
      t.string :type, null: false
      t.timestamp :executed_at, null: false
      t.string :vendor
      t.float :quantity
      t.float :value
      t.timestamps
    end
  end
end
