require "test_helper"

class PositionTest < ActiveSupport::TestCase

  setup do
    @account = Account.create!(institution_name: "Robinhood", name: "One")
    @other = Account.create!(institution_name: "Fidelity", name: "Two")
    @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
    @as_of = Time.current.change(usec: 0)
  end

  def quote(asset, price)
    Quote.create!(asset: asset, price: price, quoted_at: Time.current)
  end

  def build_position(account: @account, asset: @asset, as_of: @as_of, **attributes)
    Position.create!({account: account, asset: asset, as_of: as_of, units: 10}.merge(attributes))
  end

  test "value and cost basis are derived on save" do
    position = build_position(units: 4, price: 25.0, average_price: 20.0)
    assert_in_delta 100.0, position.value, 0.001
    assert_in_delta 80.0, position.cost_basis, 0.001
  end

  test "value is nil without a price" do
    position = build_position(price: nil)
    assert_nil position.value
    assert_nil position.cost_basis
  end

  test "as_of defaults to the account's current snapshot" do
    @account.update!(positions_as_of: @as_of)
    position = Position.create!(account: @account, asset: @asset, units: 1)
    assert_equal @as_of, position.as_of
  end

  test "portfolio sums units across accounts" do
    quote(@asset, 12.0)
    build_position(account: @account, units: 10)
    build_position(account: @other, units: 5)

    holdings = Position.where(as_of: @as_of).portfolio
    assert_equal 1, holdings.length
    assert_equal "SCTY", holdings.first[:symbol]
    assert_in_delta 15, holdings.first[:units], 0.001
    assert_in_delta 180, holdings.first[:value], 0.001
  end

  test "portfolio prices off the cached quote, not the broker price" do
    quote(@asset, 12.0)
    build_position(units: 10, price: 99.0)

    holding = Position.where(as_of: @as_of).portfolio.first
    assert_in_delta 12.0, holding[:price], 0.001
    assert_in_delta 120.0, holding[:value], 0.001
  end

  test "portfolio falls back to the broker price when nothing is quoted" do
    build_position(units: 10, price: 99.0)

    holding = Position.where(as_of: @as_of).portfolio.first
    assert_in_delta 99.0, holding[:price], 0.001
    assert_in_delta 990.0, holding[:value], 0.001
  end

  test "portfolio drops holdings that are not held" do
    build_position(units: 0)
    assert_empty Position.where(as_of: @as_of).portfolio
  end

  test "current returns only each account's newest snapshot" do
    older = @as_of - 1.day
    build_position(as_of: older, units: 3)
    build_position(as_of: @as_of, units: 7)
    @account.update!(positions_as_of: @as_of)

    assert_equal [7.0], Position.current.pluck(:units)
  end

  test "current spans accounts snapshotted at different times" do
    @account.update!(positions_as_of: @as_of)
    build_position(account: @account, as_of: @as_of, units: 7)

    other_as_of = @as_of - 3.hours
    @other.update!(positions_as_of: other_as_of)
    build_position(account: @other, as_of: other_as_of, units: 2)
    build_position(account: @other, as_of: @as_of - 5.hours, units: 99)

    assert_equal [2.0, 7.0], Position.current.pluck(:units).sort
  end

  test "cash is valued at face without a quote" do
    cash = Asset.create!(symbol: "USD", type: "cash", splits_updated_at: Time.current)
    build_position(asset: cash, units: 250.0)

    holding = Position.where(as_of: @as_of).portfolio.first
    assert_in_delta 1.0, holding[:price], 0.001
    assert_in_delta 250.0, holding[:value], 0.001
  end

end
