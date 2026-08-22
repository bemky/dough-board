require "test_helper"

class AssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    # splits_updated_at keeps the create callback from queuing a LoadSplitsJob.
    @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
  end

  test "edit renders the form for the asset" do
    get edit_asset_path(@asset)
    assert_response :success
    assert_select "input[name=?][value=?]", "asset[symbol]", "SCTY"
  end

  test "update persists permitted attributes and returns to the portfolio" do
    patch asset_path(@asset), params: {asset: {name: "SolarCity", type: "stock", exchange: "nasdaq"}}
    assert_redirected_to assets_path

    @asset.reload
    assert_equal "SolarCity", @asset.name
    assert_equal "stock", @asset.type
    assert_equal "nasdaq", @asset.exchange
  end

  # The form's selects carry a blank option, so untouched optional fields come
  # back as "" — which allow_nil does not cover.
  test "update accepts the blank selects the form submits" do
    patch asset_path(@asset), params: {asset: {symbol: "SCTY", name: "", type: "crypto", exchange: ""}}
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
