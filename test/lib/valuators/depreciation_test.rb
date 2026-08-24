require "test_helper"

class DepreciationValuatorTest < ActiveSupport::TestCase

  def asset(settings)
    Asset.new(symbol: "VEHICLE:2019-OUTBACK", type: "vehicle", valuation_key: settings)
  end

  test "a car bought today is worth what was paid for it" do
    price = Valuators::Depreciation.price(asset(
      "purchase_price" => "30000", "purchased_on" => Date.current.to_s
    ))
    assert_in_delta 30_000, price, 0.01
  end

  test "value decays at the default rate a year" do
    price = Valuators::Depreciation.price(asset(
      "purchase_price" => "30000", "purchased_on" => (Date.current - 365).to_s
    ))
    # 15% off the first year.
    assert_in_delta 25_500, price, 10.0
  end

  test "the rate compounds rather than running out" do
    price = Valuators::Depreciation.price(asset(
      "purchase_price" => "30000", "purchased_on" => (Date.current - 1095).to_s
    ))
    assert_in_delta 30_000 * (0.85**3), price, 10.0
  end

  test "an entered rate overrides the default, as a percentage" do
    price = Valuators::Depreciation.price(asset(
      "purchase_price" => "30000", "purchased_on" => (Date.current - 365).to_s,
      "annual_rate" => "25"
    ))
    assert_in_delta 22_500, price, 10.0
  end

  # An exponential decay left alone approaches zero, and a 20-year-old car is
  # not worth nothing.
  test "the curve stops at a floor" do
    settings = {"purchase_price" => "30000", "purchased_on" => (Date.current - (365 * 40)).to_s}
    assert_in_delta 3_000, Valuators::Depreciation.price(asset(settings)), 0.01

    assert_in_delta 1_200, Valuators::Depreciation.price(asset(settings.merge("residual_value" => "1200"))), 0.01
  end

  # A date in the future is a typo, not a car that hasn't lost value yet.
  test "a future purchase date is worth the purchase price, not more" do
    price = Valuators::Depreciation.price(asset(
      "purchase_price" => "30000", "purchased_on" => (Date.current + 30).to_s
    ))
    assert_in_delta 30_000, price, 0.01
  end

  # Nil is the contract for "this source can't answer", and it's what keeps the
  # blank Quote from being persisted.
  test "settings that aren't filled in yet produce no price" do
    assert_nil Valuators::Depreciation.price(asset({}))
    assert_nil Valuators::Depreciation.price(asset("purchase_price" => "30000"))
    assert_nil Valuators::Depreciation.price(asset("purchased_on" => Date.current.to_s))
    assert_nil Valuators::Depreciation.price(Asset.new(symbol: "VEHICLE:X", type: "vehicle"))
  end

  test "an unusable rate is refused rather than turned into a curve" do
    settings = {"purchase_price" => "30000", "purchased_on" => Date.current.to_s}
    assert_nil Valuators::Depreciation.price(asset(settings.merge("annual_rate" => "0")))
    assert_nil Valuators::Depreciation.price(asset(settings.merge("annual_rate" => "150")))
  end

  test "an unparseable date produces no price" do
    assert_nil Valuators::Depreciation.price(asset(
      "purchase_price" => "30000", "purchased_on" => "12/34/5678"
    ))
  end

end
