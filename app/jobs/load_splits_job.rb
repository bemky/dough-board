# Scrapes an asset's split history and recomputes adjusted_quantity for every
# transaction against it. Runs off-request because splithistory.com is slow and
# can be down: transactions save immediately with an unadjusted quantity and are
# corrected when this lands.
class LoadSplitsJob < ApplicationJob
  queue_as :default

  # Skipped when the asset no longer exists (deleted between enqueue and run).
  discard_on ActiveJob::DeserializationError

  def perform(asset, force: false)
    asset.load_splits(force)

    # Sharing this asset instance keeps load_splits from re-scraping per row,
    # and force is required because set_adjusted_quantity is a no-op once
    # adjusted_quantity is set.
    asset.transactions.each do |transaction|
      transaction.asset = asset
      transaction.set_adjusted_quantity!(true)
    end
  end
end
