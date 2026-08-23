# Where an account's holdings come from.
#
# "transactions" — DerivePositionsJob owns the positions, folding them from the
#   account's own transactions on every run. Editing one by hand would be undone
#   within the hour, so the UI doesn't offer to.
# "manual" — the positions are the record of truth and nothing rewrites them.
#   For a holding no transaction history covers.
#
# A connector adds a third value later; it is the same idea, just a different
# thing doing the writing.
class AddPositionsSourceToAccounts < ActiveRecord::Migration[8.1]
  def change
    # Existing accounts are all fed by their transactions, which is also the
    # right default for a hand-created one — an account with no transactions
    # derives to nothing rather than to something wrong.
    add_column :accounts, :positions_source, :string, null: false, default: "transactions"
  end
end
