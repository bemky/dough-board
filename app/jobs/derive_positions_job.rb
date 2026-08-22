# Folds an account's transactions into Position rows.
#
# Accounts fed by a connector get their positions from the brokerage, which
# knows about corporate actions and transfers we never see. Accounts filled in
# from a CSV have only their transactions, so this reconstructs the same shape
# from them — the portfolio then reads one table either way.
#
# Accounts whose positions are maintained by hand are left entirely alone: this
# job rewrites and prunes the whole snapshot, so there is no such thing as
# partially owning one.
class DerivePositionsJob < ApplicationJob
  queue_as :default

  # Skipped when the account no longer exists (deleted between enqueue and run).
  discard_on ActiveJob::DeserializationError

  # With no `as_of`, this corrects the account's current snapshot in place —
  # what a hand-edited transaction wants, and what keeps an import of hundreds
  # of rows from writing hundreds of points into the history. The periodic rake
  # task passes a timestamp to append a new point instead.
  def perform(account, as_of: nil)
    return unless account.derives_positions?

    as_of ||= account.positions_as_of || Time.current

    # Deliberately not `account.transactions` — an Account handed to two runs in
    # one process would serve the second one whatever the first had loaded.
    units = Hash.new(0.0)
    Transaction.where(account_id: account.id).each do |transaction|
      moved = transaction.units
      units[transaction.asset_id] += moved if moved
    end

    held = units.filter { |_, quantity| quantity.round(8) > 0 }

    held.each do |asset_id, quantity|
      position = Position.find_or_initialize_by(account_id: account.id, asset_id: asset_id, as_of: as_of)
      # A derived position has no broker price or cost basis behind it; price it
      # off the cached quote so it values the same way the old fold did.
      position.units = quantity
      position.price = position.asset.cached_price
      position.save!
    end

    # Anything sold down to nothing since the last run.
    Position.where(account_id: account.id, as_of: as_of).where.not(asset_id: held.keys).delete_all

    account.update!(positions_as_of: as_of)
  end
end
