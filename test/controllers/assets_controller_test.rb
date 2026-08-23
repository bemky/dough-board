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

  test "update re-renders edit with the errors when the record is invalid" do
    patch asset_path(@asset), params: {asset: {type: "bond"}}
    assert_response :bad_request
    assert_nil @asset.reload.type
    assert_select "li", text: "Type is not included in the list"
  end
end
