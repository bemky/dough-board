require "test_helper"

class QuoteTest < ActiveSupport::TestCase

  # Every source is reached the same way, so a test can stand in for one by
  # replacing the singleton's #price.
  def with_price(valuator, price, &block)
    instance = valuator.instance
    instance.define_singleton_method(:price) { |_asset| price }
    yield
  ensure
    instance.singleton_class.remove_method(:price)
  end

  test "a security's price comes from Finnhub" do
    asset = Asset.create!(symbol: "SCTY", type: "stock", splits_updated_at: Time.current)

    with_price(Valuators::Finnhub, 49.71) do
      quote = Quote.create(asset: asset)
      assert quote.persisted?
      assert_in_delta 49.71, quote.price, 0.001
    end
  end

  # The whole point of the valuator layer: nothing here knows what a car is.
  test "a car's price comes from its own source, not Finnhub" do
    asset = Asset.create!(symbol: "VEHICLE:2019-OUTBACK", type: "vehicle",
      valuation_key: {"purchase_price" => "30000", "purchased_on" => Date.current.to_s})

    with_price(Valuators::Finnhub, 49.71) do
      quote = Quote.create(asset: asset)
      assert quote.persisted?
      assert_in_delta 30_000, quote.price, 0.01
    end
  end

  # A blank quote must never be persisted, or cached_price starts answering with
  # a price of nil for an asset that has one.
  test "a source with nothing to say leaves no quote behind" do
    # A house has no source at all until someone types a value in, and a car
    # with no settings yet can't be depreciated from anything.
    [Asset.create!(symbol: "PROPERTY:12-OAK-ST", type: "real_estate"),
     Asset.create!(symbol: "VEHICLE:2019-OUTBACK", type: "vehicle")].each do |asset|
      quote = Quote.create(asset: asset)
      assert_not quote.persisted?
      assert_empty asset.quotes.reload
    end
  end

  test "cash never reaches a source at all" do
    asset = Asset.create!(symbol: "USD", type: "cash")

    with_price(Valuators::Finnhub, 49.71) do
      assert_not Quote.create(asset: asset).persisted?
    end
    assert_equal 1.0, asset.price
  end

  # A price handed in is the answer; the manual valuator has nothing to add.
  test "a quote created with a price of its own is kept as-is" do
    asset = Asset.create!(symbol: "PROPERTY:12-OAK-ST", type: "real_estate",
      valuation_source: "manual")

    quote = Quote.create!(asset: asset, price: 800_000, quoted_at: Time.current)
    assert_in_delta 800_000, quote.reload.price, 0.01
  end

end
