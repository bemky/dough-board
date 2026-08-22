require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    @account = Account.create!(institution_name: "Robinhood", name: "Brokerage")
    @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
    Quote.create!(asset: @asset, price: 20.0, quoted_at: Time.current)

    @as_of = Time.current.change(usec: 0)
    Position.create!(account: @account, asset: @asset, as_of: @as_of, units: 10, price: 20.0)
    @account.update!(positions_as_of: @as_of)
  end

  test "index values accounts from their current positions" do
    get accounts_path
    assert_response :success
    assert_select "td", text: "$200.00"
  end

  test "show renders the account's holdings" do
    get account_path(@account)
    assert_response :success
    assert_select "[data-portfolio-total]", text: /\$200\.00/
    assert_select "[data-quote-symbol=?]", "SCTY"
  end

  test "an older snapshot is not counted" do
    Position.create!(account: @account, asset: @asset, as_of: @as_of - 1.day, units: 999, price: 20.0)

    get account_path(@account)
    assert_response :success
    assert_select "[data-portfolio-total]", text: /\$200\.00/
  end
end

class AssetsPortfolioTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
    Quote.create!(asset: @asset, price: 20.0, quoted_at: Time.current)
    @as_of = Time.current.change(usec: 0)
  end

  def position_for(account_name, units)
    account = Account.create!(institution_name: "Robinhood", name: account_name)
    Position.create!(account: account, asset: @asset, as_of: @as_of, units: units, price: 20.0)
    account.update!(positions_as_of: @as_of)
    account
  end

  test "the portfolio sums each account's current snapshot" do
    position_for("One", 10)
    position_for("Two", 5)

    get assets_path
    assert_response :success
    assert_select "td", text: "15.0"
  end

  test "a snapshot the account has moved past is ignored" do
    account = position_for("One", 10)
    Position.create!(account: account, asset: @asset, as_of: @as_of - 1.day, units: 999, price: 20.0)

    get assets_path
    assert_response :success
    assert_select "td", text: "10.0"
  end
end
