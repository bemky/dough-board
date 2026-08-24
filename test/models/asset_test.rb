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

  test "an account reported only as a balance is dollars held, and never quoted" do
    balance = Asset.create!(symbol: "FUND:TITAN-FLAGSHIP", type: "balance",
      splits_updated_at: Time.current)

    assert balance.face_value?
    assert_not balance.splittable?
    assert_equal 1.0, balance.price
    assert_equal 1.0, balance.cached_price
    # Nothing quotes a FUND: symbol, and #price must not go asking.
    assert_empty balance.quotes.reload
  end

  test "a type resolves to the source that can price it" do
    assert_equal Valuators::Finnhub, @asset.valuator
    assert_equal Valuators::Finnhub, Asset.new(symbol: "BTC", type: "crypto").valuator
    assert_equal Valuators::Manual, Asset.new(symbol: "PROPERTY:X", type: "real_estate").valuator
    assert_equal Valuators::Depreciation, Asset.new(symbol: "VEHICLE:X", type: "vehicle").valuator
  end

  test "a source named on the asset wins over the one its type implies" do
    asset = Asset.new(symbol: "PROPERTY:X", type: "real_estate", valuation_source: "depreciation")
    assert_equal Valuators::Depreciation, asset.valuator
  end

  test "changing the valuation settings clears cached quotes" do
    # A different purchase price is a different curve.
    @asset.update!(valuation_key: {"purchase_price" => "30000"})
    assert_empty @asset.quotes.reload

    quote = Quote.create!(asset: @asset, price: 10, quoted_at: Time.current)
    @asset.update!(valuation_source: "manual")
    assert_not Quote.exists?(quote.id)
  end

  # splithistory.com would happily be asked for "PROPERTY:12-OAK-ST".
  test "a house and a car have no split history to scrape" do
    house = Asset.create!(symbol: "PROPERTY:12-OAK-ST", type: "real_estate")
    assert_not house.splittable?
    assert_not Asset.new(symbol: "VEHICLE:X", type: "vehicle").splittable?
    assert @asset.splittable?

    assert_no_enqueued_jobs(only: LoadSplitsJob) do
      house.update!(symbol: "PROPERTY:14-OAK-ST")
    end

    with_scraped_splits([[DateTime.new(2016, 6, 1), 3.0]]) do
      assert_empty house.load_splits(true)
    end
  end

  test "a hand-entered value is recorded as a quote" do
    house = Asset.create!(symbol: "PROPERTY:12-OAK-ST", type: "real_estate")
    house.update!(entered_value: "742500")

    assert_in_delta 742_500, house.cached_price, 0.01
    assert_nil house.entered_value
  end

  # cached_quote's window belongs to the valuator: Finnhub's is a cache of
  # something that moves by the minute, a value someone typed in never expires.
  test "how long a quote stands depends on where it came from" do
    @quote.update!(quoted_at: 3.days.ago)
    assert_nil @asset.reload.cached_quote

    house = Asset.create!(symbol: "PROPERTY:12-OAK-ST", type: "real_estate")
    Quote.create!(asset: house, price: 742_500, quoted_at: 3.weeks.ago)
    assert_in_delta 742_500, house.cached_price, 0.01
  end

  # Distinct from the window above: a stock is re-quoted every half hour but its
  # last quote stays usable for a day; a car is the other way round.
  test "how often a source is asked again depends on where it came from" do
    assert @asset.quote_due?, "a stock is due every run"

    car = Asset.create!(symbol: "VEHICLE:2019-OUTBACK", type: "vehicle")
    assert car.quote_due?, "a car with no value yet is due"

    quote = Quote.create!(asset: car, price: 25_500, quoted_at: 2.hours.ago)
    assert_not car.reload.quote_due?, "recomputed two hours ago is not due"

    quote.update!(quoted_at: 2.days.ago)
    assert car.reload.quote_due?
  end

  # The one source nothing ever asks: a house's value moves when you say it
  # does, and a refresh that asked would only overwrite it with nothing.
  test "a hand-maintained value is never asked for again" do
    house = Asset.create!(symbol: "PROPERTY:12-OAK-ST", type: "real_estate",
      entered_value: "742500")

    assert_equal Valuators::Manual, house.valuator
    assert_not house.quote_due?
    assert_in_delta 742_500, house.price, 0.01
    assert_equal 1, house.quotes.reload.count
  end
end
