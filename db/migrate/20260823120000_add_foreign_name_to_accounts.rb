class AddForeignNameToAccounts < ActiveRecord::Migration[8.1]
  def up
    add_column :accounts, :foreign_name, :string

    # Every synced account's name is, right now, whatever the institution last
    # reported — nothing else could have written it. Record that so a rename
    # from here on reads as a rename.
    execute <<~SQL
      UPDATE accounts SET foreign_name = name WHERE connection_id IS NOT NULL
    SQL
  end

  def down
    remove_column :accounts, :foreign_name
  end
end
