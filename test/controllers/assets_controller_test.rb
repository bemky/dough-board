require "test_helper"

class AssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    # splits_updated_at keeps the create callback from queuing a LoadSplitsJob.
    @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
    @nasdaq = Exchange.create!(code: "NASDAQ", name: "Nasdaq Stock Market")
  end

  test "the portfolio nets what's owed against what's held" do
    account = Account.create!(institution_name: "Testbank", name: "Card", positions_source: "connection")
    debt = Asset.create!(symbol: "DEBT:CREDIT_CARD", name: "Credit Card Debt",
      type: "liability", splits_updated_at: Time.current)
    as_of = Time.current
    Position.create!(account: account, asset: @asset, as_of: as_of, units: 10, price: 100.0)
    Position.create!(account: account, asset: debt, as_of: as_of, units: -250.0, price: 1.0)
    account.update!(positions_as_of: as_of)

    get assets_path
    assert_response :success

    assert_select "[data-portfolio-total]", text: /\$750\.00/
    assert_select "[data-portfolio-assets]", text: /\$1,000\.00/
    assert_select "body", text: /Credit Card Debt/
  end

  test "edit renders the form for the asset" do
    get edit_asset_path(@asset)
    assert_response :success
    assert_select "input[name=?][value=?]", "asset[symbol]", "SCTY"
  end

  test "update persists permitted attributes and returns to the portfolio" do
    patch asset_path(@asset), params: {asset: {name: "SolarCity", type: "stock", exchange_id: @nasdaq.id}}
    assert_redirected_to assets_path

    @asset.reload
    assert_equal "SolarCity", @asset.name
    assert_equal "stock", @asset.type
    assert_equal @nasdaq, @asset.exchange
  end

  # The form's selects carry a blank option, so untouched optional fields come
  # back as "" — which allow_nil does not cover.
  test "update accepts the blank selects the form submits" do
    patch asset_path(@asset), params: {asset: {symbol: "SCTY", name: "", type: "crypto", exchange_id: ""}}
    assert_redirected_to assets_path

    @asset.reload
    assert_equal "crypto", @asset.type
    assert_nil @asset.exchange
  end

  # A house has no ticker and no transactions, so nothing else would ever
  # create it.
  test "new renders a blank form" do
    get new_asset_path
    assert_response :success
    assert_select "select[name=?]", "asset[valuation_source]"
    # One fieldset per source, which the JS shows and hides by this attribute.
    assert_select "[data-valuator-fields=?]", "depreciation"
    assert_select "input[name=?]", "asset[valuation_key][purchase_price]"
    assert_select "input[name=?]", "asset[valuation_key][purchased_on]"
  end

  test "create adds an asset with the value entered for it" do
    post create_asset_path, params: {asset: {
      symbol: "PROPERTY:12-OAK-ST", name: "Home", type: "real_estate",
      entered_value: "742500"
    }, redirect_to: assets_path}
    assert_redirected_to assets_path

    house = Asset.find_by(symbol: "PROPERTY:12-OAK-ST")
    assert_equal "real_estate", house.type
    assert_equal Valuators::Manual, house.valuator
    assert_in_delta 742_500, house.cached_price, 0.01
  end

  test "create adds an asset with its valuation settings" do
    post create_asset_path, params: {asset: {
      symbol: "VEHICLE:2019-OUTBACK", name: "Outback", type: "vehicle",
      valuation_key: {purchase_price: "30000", purchased_on: Date.current.to_s}
    }, redirect_to: assets_path}
    assert_redirected_to assets_path

    car = Asset.find_by(symbol: "VEHICLE:2019-OUTBACK")
    assert_equal Valuators::Depreciation, car.valuator
    assert_equal "30000", car.valuation_key["purchase_price"]
    assert_in_delta 30_000, car.price, 0.01
  end

  # valuation_key is a json column: permitting it wholesale would let a form
  # post write arbitrary JSON onto an asset.
  test "create keeps keys no valuator declared out of valuation_key" do
    post create_asset_path, params: {asset: {
      symbol: "VEHICLE:2019-OUTBACK", type: "vehicle",
      valuation_key: {purchase_price: "30000", purchased_on: "2019-06-01", whatever: "no"}
    }, redirect_to: assets_path}

    car = Asset.find_by(symbol: "VEHICLE:2019-OUTBACK")
    assert_equal %w(purchase_price purchased_on), car.valuation_key.keys.sort
  end

  test "update records a hand-entered value as a quote" do
    patch asset_path(@asset), params: {asset: {entered_value: "123.45"}}
    assert_redirected_to assets_path
    assert_in_delta 123.45, @asset.reload.cached_price, 0.001
  end

  test "update re-renders edit with the errors when the record is invalid" do
    patch asset_path(@asset), params: {asset: {type: "bond"}}
    assert_response :bad_request
    assert_nil @asset.reload.type
    assert_select "li", text: "Type is not included in the list"
  end
end
