require "test_helper"

class ValuatorsTest < ActiveSupport::TestCase

  class Echo < Valuators::Base
    def price(asset, at: nil)
      {asset: asset, at: at}
    end
  end

  test "for resolves a registered valuator" do
    assert_equal Valuators::Depreciation, Valuators.for("depreciation")
  end

  test "for rejects an unknown valuator" do
    assert_raises(ArgumentError) { Valuators.for("nope") }
  end

  # Same trap as Connectors::Base: without **kwargs on method_missing, Ruby 3
  # collects a call's keywords into a positional Hash.
  test "class-level delegation carries keyword arguments through" do
    assert_equal({asset: :an_asset, at: :a_time}, Echo.price(:an_asset, at: :a_time))
  end

  test "the base interface refuses to guess a price" do
    assert_raises(NotImplementedError) { Valuators::Base.instance.price(nil) }
  end

  # These are what Asset#cached_quote and #quote_due? read, so a valuator that
  # forgot to answer would silently change how often the app goes out.
  test "the base defaults are the behaviour Finnhub has always had" do
    assert_equal 24.hours, Valuators::Finnhub.quote_ttl
    assert_equal 0.seconds, Valuators::Finnhub.refresh_interval
  end

  # A number that only changes when someone changes it is the best one anyone
  # has; expiring it would blank the holding out rather than improve it.
  test "the sources that are asked rarely keep their last answer indefinitely" do
    assert_nil Valuators::Depreciation.quote_ttl
    assert_nil Valuators::Manual.quote_ttl
  end

  test "a hand-entered value is never refreshed away" do
    assert_nil Valuators::Manual.refresh_interval
    assert_nil Valuators::Manual.price(Asset.new(symbol: "PROPERTY:12-OAK-ST"))
  end

  # AssetACL permits valuation_key key by key off this list; a key a valuator
  # reads but doesn't declare would be silently dropped by strong params.
  test "key_names covers every key the valuators read" do
    assert_includes Valuators.key_names, "purchase_price"
    assert_includes Valuators.key_names, "purchased_on"
    assert_includes Valuators.key_names, "annual_rate"
  end

  test "selectable offers a label per configured valuator" do
    labels = Valuators.selectable.to_h.invert
    assert_equal "Depreciation", labels["depreciation"]
    assert_equal "Manual", labels["manual"]
  end

end
