require "test_helper"

class DemoControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    @account = Account.create!(institution_name: "Robinhood", name: "Brokerage",
      positions_source: "manual")
    @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
    @as_of = Time.current.change(usec: 0)
    @account.update!(positions_as_of: @as_of)
    Position.create!(account: @account, asset: @asset, as_of: @as_of,
      units: 10, price: 20.0, average_price: 15.0)
  end

  test "the toggle turns the demo on for this browser and off again" do
    get positions_path
    assert_select "td", text: "10.0"

    # The toggle sends you back to the page you were reading, which is the whole
    # point of it being in the header.
    post demo_path, headers: {"HTTP_REFERER" => positions_url}
    assert_redirected_to positions_url

    get positions_path
    # Whatever the digest happens to make of "SCTY", it is not what's held.
    assert_select "td", text: "10.0", count: 0
    assert_select "td", text: "$200.00", count: 0

    post demo_path
    get positions_path
    assert_select "td", text: "10.0"
  end

  test "a demo holding is the same size on every page that shows it" do
    post demo_path

    get positions_path
    units = css_select("td[data-label=Units]").first.text.to_f

    get assets_path
    assert_equal units, css_select("td[data-label=Units]").first.text.to_f
    assert_operator units, :>, 10 * DemoMode::MINIMUM * 0.999
    assert_operator units, :<, 10 * DemoMode::MAXIMUM * 1.001
  end

  test "a demo can't be switched off when the deployment is the demo" do
    ENV["DEMO_MODE"] = "true"
    post demo_path

    follow_redirect!
    assert_select "td", text: "10.0", count: 0
    assert_match "whole deployment", flash[:alert]
  ensure
    ENV.delete("DEMO_MODE")
  end

  test "logging in is still what stands between the demo and a stranger" do
    delete logout_path
    post demo_path
    assert_redirected_to login_path(redirect_to: "/demo")
  end

end
