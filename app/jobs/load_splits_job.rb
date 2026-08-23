# Scrapes an asset's split history and recomputes adjusted_quantity for every
# transaction against it. Runs off-request because splithistory.com is slow and
# can be down: transactions save immediately with an unadjusted quantity and are
# corrected when this lands.
class LoadSplitsJob < ApplicationJob
  # Its own queue: a sync creates an asset per new symbol, so these arrive in
  # the thousands and each one waits on a slow third-party page. On `default`
  # they sat in front of whatever a person was waiting for. See
  # config/sidekiq.yml for the weighting.
  queue_as :scrapes

  # Skipped when the asset no longer exists (deleted between enqueue and run).
  discard_on ActiveJob::DeserializationError

  def perform(asset, force: false)
    asset.load_splits(force)

    account_ids = Set.new

    # Every one of these saves would otherwise enqueue its own derivation, and
    # they all correct the same snapshot — an asset held across a few hundred
    # transactions produced a few hundred identical jobs. Fold once per account
    # afterwards instead, the same way the CSV import does.
    Transaction.without_position_derivation do
      # Sharing this asset instance keeps load_splits from re-scraping per row,
      # and force is required because set_adjusted_quantity is a no-op once
      # adjusted_quantity is set.
      asset.transactions.each do |transaction|
        transaction.asset = asset
        transaction.set_adjusted_quantity!(true)
        account_ids << transaction.account_id
      end
    end

    # Only the accounts whose positions are folded from transactions: a synced
    # or hand-maintained account's holdings don't move because a split landed.
    Account.where(id: account_ids).find_each do |account|
      DerivePositionsJob.perform_later(account) if account.derives_positions?
    end
  end
end
