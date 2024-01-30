class CreateAssets < ActiveRecord::Migration[7.1]
  def change
    create_table :assets do |t|
      t.string :name
      t.string :symbol, null: false
      t.string :exchange
      t.string :type
      t.timestamps
    end
  end
end
