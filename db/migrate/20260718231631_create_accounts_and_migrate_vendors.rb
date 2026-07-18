class CreateAccountsAndMigrateVendors < ActiveRecord::Migration[8.1]
  class MigrationAccount < ActiveRecord::Base
    self.table_name = "accounts"
  end

  class MigrationTransaction < ActiveRecord::Base
    self.table_name = "transactions"
  end

  def up
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :number
      t.string :provider

      t.timestamps
    end

    add_reference :transactions, :account, foreign_key: true

    vendors = MigrationTransaction.distinct.pluck(:vendor)
    blank_vendors, present_vendors = vendors.partition { |vendor| vendor.blank? }

    unknown_account = MigrationAccount.create!(provider: "Unknown", name: "Unknown Account")
    MigrationTransaction.where(vendor: blank_vendors).update_all(account_id: unknown_account.id)

    present_vendors.each do |vendor|
      account = MigrationAccount.create!(provider: vendor, name: "#{vendor} Account")
      MigrationTransaction.where(vendor: vendor).update_all(account_id: account.id)
    end

    change_column_null :transactions, :account_id, false

    remove_column :transactions, :vendor, :string
  end

  def down
    add_column :transactions, :vendor, :string

    change_column_null :transactions, :account_id, true

    MigrationTransaction.reset_column_information
    MigrationTransaction.find_each do |transaction|
      account = MigrationAccount.find_by(id: transaction.account_id)
      next unless account
      transaction.update_column(:vendor, account.provider == "Unknown" ? nil : account.provider)
    end

    remove_reference :transactions, :account, foreign_key: true

    drop_table :accounts
  end
end
