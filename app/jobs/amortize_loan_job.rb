# Writes an amortized account's one position: what's still owed on its loan,
# worked out from the terms rather than looked up anywhere.
#
# Mirrors DerivePositionsJob's snapshot contract exactly — no `as_of` corrects
# the current snapshot in place, an `as_of` (from `positions:derive`, hourly)
# appends a history point, and anything else in that snapshot is pruned. Because
# the balance can be asked for any date, the history this leaves behind is a
# real paydown curve rather than a series of guesses.
class AmortizeLoanJob < ApplicationJob
  queue_as :default

  # Skipped when the account no longer exists (deleted between enqueue and run).
  discard_on ActiveJob::DeserializationError

  def perform(account, as_of: nil)
    return unless account.amortized_positions?

    amortization = account.amortization
    return if amortization.nil?

    as_of ||= account.positions_as_of || Time.current
    balance = amortization.balance(on: as_of.to_date)

    # A debt is negative units of dollars at face value — the same shape the
    # Plaid connector writes, so a mortgage kept here and one synced from a
    # lender add up together instead of sitting in two different lines.
    if balance.positive?
      asset = debt_asset(account)
      position = Position.find_or_initialize_by(account_id: account.id, asset_id: asset.id, as_of: as_of)
      position.units = -balance
      position.price = 1.0
      position.save!
      kept = [asset.id]
    else
      # Paid off. Not a holding, the same way a share sold down to nothing isn't.
      kept = []
    end

    Position.where(account_id: account.id, as_of: as_of).where.not(asset_id: kept).delete_all
    account.update!(positions_as_of: as_of)
  end

  # The asset is the *kind* of debt, created on first use with the same name a
  # sync would have given it.
  private def debt_asset(account)
    symbol = account.debt_symbol
    Asset.find_or_create_by!(symbol: symbol) do |asset|
      asset.type = "liability"
      asset.name = Asset::DEBT_NAMES[symbol]
    end
  end
end
