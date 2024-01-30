class CreateSplits < ActiveRecord::Migration[7.1]
  def change
    create_table :splits do |t|
      t.belongs_to :asset
      t.float :ratio
      t.timestamp :split_at
      t.timestamps
    end
    add_column :transactions, :adjusted_quantity, :float
    add_column :assets, :splits_updated_at, :timestamp
  end
end
