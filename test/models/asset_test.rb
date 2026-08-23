require "test_helper"

class AssetTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @asset = Asset.create!(symbol: "SCTY", type: "stock", splits_updated_at: Time.current)
    @quote = Quote.create!(asset: @asset, price: 49.71, quoted_at: Time.current)
  end

  # The scraper is a singleton delegated to by SplitHistoryScraper.splits, so a
  # singleton method on the instance keeps the tests off the network.
  def with_scraped_splits(pairs)
    scraper = SplitHistoryScraper.instance
    scraper.define_singleton_method(:splits) { |_symbol| pairs }
    yield
  ensure
    scraper.singleton_class.remove_method(:splits)
  end

  test "changing symbol clears splits and queues a rescrape" do
    account = Account.create!(institution_name: "Robinhood", name: "Model Test")
    Split.create!(asset: @asset, split_at: Date.new(2016, 1, 1), ratio: 2)
    transaction = Transaction.create!(account: account, asset: @asset, type: "buy",
      executed_at: Date.new(2015, 1, 1), quantity: 10, value: 100, adjusted_quantity: 20)

    assert_enqueued_with job: LoadSplitsJob, args: [@asset] do
      @asset.update!(symbol: "TSLA")
    end
    assert_empty @asset.splits.reload
    assert_nil @asset.reload.splits_updated_at

    # The new symbol has a 3-for-1 after the execution date, not the old 2-for-1.
    with_scraped_splits([[DateTime.new(2016, 6, 1), 3.0]]) do
      perform_enqueued_jobs
    end

    assert_equal [3.0], @asset.splits.reload.map(&:ratio)
    assert_in_delta 30, transaction.reload.adjusted_quantity, 0.001
  end

  test "changing symbol clears cached quotes" do
    @asset.update!(symbol: "TSLA")
    assert_empty @asset.quotes.reload
    assert_not Quote.exists?(@quote.id)
  end

  test "changing type clears cached quotes" do
    # stock -> crypto changes quote_symbol from "BTC" to "BINANCE:BTCUSDT".
    @asset.update!(type: "crypto")
    assert_empty @asset.quotes.reload
  end

  test "changing an unrelated attribute keeps cached quotes" do
    @asset.update!(name: "SolarCity", exchange: Exchange.create!(code: "NASDAQ", name: "Nasdaq Stock Market"))
    assert_equal [@quote.id], @asset.quotes.reload.map(&:id)
  end

  test "re-saving the same symbol keeps cached quotes" do
    # normalizes upcases, so a lowercase write is not a change.
    @asset.update!(symbol: "scty")
    assert_equal [@quote.id], @asset.quotes.reload.map(&:id)
  end

  test "a debt is dollars owed: worth face value, and never quoted" do
    debt = Asset.create!(symbol: "DEBT:HOME_LOAN", type: "liability", splits_updated_at: Time.current)

    assert debt.liability?
    assert_equal 1.0, debt.price
    assert_equal 1.0, debt.cached_price
    # #price would otherwise create a Quote, which fetches from Finnhub.
    assert_empty debt.quotes.reload
  end
end
