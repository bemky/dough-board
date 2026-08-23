require "test_helper"

class LoadSplitsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = Account.create!(institution_name: "Robinhood", name: "Brokerage")
    @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
  end

  def buy(quantity: 10, account: @account)
    Transaction.create!(account: account, asset: @asset, type: "buy",
      executed_at: Date.new(2015, 1, 1), quantity: quantity, value: quantity * 10)
  end

  # The whole point: an asset held across many transactions used to produce one
  # DerivePositionsJob per transaction, all of them correcting the same snapshot.
  test "one derivation per account, however many transactions it recomputes" do
    Transaction.without_position_derivation { 5.times { buy } }
    Split.create!(asset: @asset, split_at: Date.new(2016, 1, 1), ratio: 2)

    assert_enqueued_jobs 1, only: DerivePositionsJob do
      LoadSplitsJob.perform_now(@asset)
    end
  end

  test "one derivation each when the transactions span accounts" do
    other = Account.create!(institution_name: "Fidelity", name: "Other")
    Transaction.without_position_derivation do
      3.times { buy }
      2.times { buy(account: other) }
    end
    Split.create!(asset: @asset, split_at: Date.new(2016, 1, 1), ratio: 2)

    assert_enqueued_jobs 2, only: DerivePositionsJob do
      LoadSplitsJob.perform_now(@asset)
    end
  end

  test "adjusted quantities are still recomputed" do
    transaction = Transaction.without_position_derivation { buy(quantity: 10) }
    Split.create!(asset: @asset, split_at: Date.new(2016, 1, 1), ratio: 2)

    # A fresh instance, because saving the transaction above loaded and cached
    # @asset.splits while it was still empty. The job gets one either way — it
    # deserializes its argument from a GlobalID — but the test would otherwise
    # hand it a stale association and prove nothing.
    LoadSplitsJob.perform_now(Asset.find(@asset.id))

    assert_in_delta 20, transaction.reload.adjusted_quantity, 0.001
  end

  # A split changing what a transaction is worth says nothing about an account
  # whose holdings the brokerage reports directly.
  test "no derivation for an account that does not fold its transactions" do
    @account.update!(positions_source: "manual")
    Transaction.without_position_derivation { 3.times { buy } }
    Split.create!(asset: @asset, split_at: Date.new(2016, 1, 1), ratio: 2)

    assert_no_enqueued_jobs only: DerivePositionsJob do
      LoadSplitsJob.perform_now(@asset)
    end
  end

  test "an asset nothing holds queues nothing" do
    assert_no_enqueued_jobs only: DerivePositionsJob do
      LoadSplitsJob.perform_now(@asset)
    end
  end

end
