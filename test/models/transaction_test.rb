require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = Account.create!(institution_name: "Robinhood", name: "Model Test")
    @asset = Asset.create!(symbol: "SCTY")
  end

  def build_transaction(**attributes)
    Transaction.new({account: @account, asset: @asset, type: "buy",
      executed_at: Date.new(2015, 1, 1), quantity: 10, value: 100}.merge(attributes))
  end

  test "creating a transaction queues a split load for its asset" do
    assert_enqueued_with job: LoadSplitsJob, args: [@asset] do
      build_transaction.save!
    end
  end

  test "saving does not queue a load while the scrape is still fresh" do
    @asset.update!(splits_updated_at: Time.current)

    assert_no_enqueued_jobs only: LoadSplitsJob do
      build_transaction.save!
    end
  end

  test "saving uses splits already on hand and never scrapes" do
    Split.create!(asset: @asset, split_at: Date.new(2016, 1, 1), ratio: 2)
    @asset.update!(splits_updated_at: Time.current)

    # No scraper stub: a network call here would fail the test rather than
    # silently slow it down.
    transaction = build_transaction
    transaction.save!
    assert_in_delta 20, transaction.adjusted_quantity, 0.001
  end

  test "splits executed after the transaction are ignored" do
    Split.create!(asset: @asset, split_at: Date.new(2014, 1, 1), ratio: 2)
    @asset.update!(splits_updated_at: Time.current)

    transaction = build_transaction
    transaction.save!
    assert_in_delta 10, transaction.adjusted_quantity, 0.001
  end
end
