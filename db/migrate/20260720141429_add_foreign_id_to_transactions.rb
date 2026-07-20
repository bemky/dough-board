class AddForeignIdToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :foreign_id, :string
    add_index :transactions, [:account_id, :foreign_id],
      unique: true,
      where: "foreign_id IS NOT NULL"
  end
end
