require "test_helper"

class DerivePositionsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = Account.create!(institution_name: "Robinhood", name: "Manual")
    # splits_updated_at keeps saving a transaction from queuing a LoadSplitsJob.
    @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
    @other = Asset.create!(symbol: "AAPL", splits_updated_at: Time.current)
    Quote.create!(asset: @asset, price: 20.0, quoted_at: Time.current)
  end

  def buy(asset: @asset, quantity: 10, type: "buy", executed_at: Date.new(2015, 1, 1))
    Transaction.create!(account: @account, asset: asset, type: type,
      executed_at: executed_at, quantity: quantity, value: quantity * 10)
  end

  test "folds buys and sales into a position" do
    buy(quantity: 10)
    buy(quantity: 4, type: "sale")

    DerivePositionsJob.perform_now(@account)

    position = @account.current_positions.sole
    assert_equal @asset, position.asset
    assert_in_delta 6, position.units, 0.001
    assert_in_delta 20.0, position.price, 0.001
    assert_in_delta 120.0, position.value, 0.001
  end

  test "cash activities do not move units" do
    buy(quantity: 10)
    %w(dividend fee interest tax substitute_dividend).each do |type|
      buy(quantity: 3, type: type)
    end

    DerivePositionsJob.perform_now(@account)

    assert_in_delta 10, @account.current_positions.sole.units, 0.001
  end

  test "share-moving activities beyond buy and sale are counted" do
    buy(quantity: 10)
    buy(quantity: 2, type: "rei")
    buy(quantity: 3, type: "external_asset_transfer_in")
    buy(quantity: 1, type: "optionassignment")

    DerivePositionsJob.perform_now(@account)

    assert_in_delta 14, @account.current_positions.sole.units, 0.001
  end

  test "uses adjusted_quantity so splits are respected" do
    Split.create!(asset: @asset, split_at: Date.new(2016, 1, 1), ratio: 2)
    buy(quantity: 10)

    DerivePositionsJob.perform_now(@account)

    assert_in_delta 20, @account.current_positions.sole.units, 0.001
  end

  test "a second run without as_of corrects the snapshot in place" do
    buy(quantity: 10)
    DerivePositionsJob.perform_now(@account)
    first_as_of = @account.reload.positions_as_of

    buy(quantity: 5)
    DerivePositionsJob.perform_now(@account)

    assert_equal first_as_of, @account.reload.positions_as_of
    assert_equal 1, @account.positions.count
    assert_in_delta 15, @account.current_positions.sole.units, 0.001
  end

  test "a run with as_of appends a point to the history" do
    buy(quantity: 10)
    DerivePositionsJob.perform_now(@account)
    first_as_of = @account.reload.positions_as_of

    later = first_as_of + 1.hour
    DerivePositionsJob.perform_now(@account, as_of: later)

    assert_equal 2, @account.positions.count
    assert_equal later, @account.reload.positions_as_of
    assert_equal [10.0], @account.current_positions.pluck(:units)
  end

  test "a holding sold to nothing leaves the snapshot" do
    buy(asset: @asset, quantity: 10)
    buy(asset: @other, quantity: 5)
    DerivePositionsJob.perform_now(@account)
    assert_equal 2, @account.current_positions.count

    buy(asset: @other, quantity: 5, type: "sale")
    DerivePositionsJob.perform_now(@account)

    assert_equal [@asset], @account.current_positions.map(&:asset)
  end

  test "saving a transaction queues a derivation for its account" do
    assert_enqueued_with job: DerivePositionsJob, args: [@account] do
      buy
    end
  end

  test "without_position_derivation suppresses the per-row enqueue" do
    assert_no_enqueued_jobs only: DerivePositionsJob do
      Transaction.without_position_derivation { buy }
    end
  end

end
