require "test_helper"

class PositionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    @account = Account.create!(institution_name: "Robinhood", name: "Brokerage",
      positions_source: "manual")
    @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
    @as_of = Time.current.change(usec: 0)
    @account.update!(positions_as_of: @as_of)
    @position = Position.create!(account: @account, asset: @asset, as_of: @as_of,
      units: 10, price: 20.0, average_price: 15.0)
  end

  test "index lists the current snapshot" do
    get positions_path
    assert_response :success
    assert_select "td", text: "10.0"
    assert_select "td", text: "$200.00"
  end

  test "index nested under an account scopes to it" do
    other = Account.create!(institution_name: "Fidelity", name: "Other")
    other_asset = Asset.create!(symbol: "AAPL", splits_updated_at: Time.current)
    other.update!(positions_as_of: @as_of)
    Position.create!(account: other, asset: other_asset, as_of: @as_of, units: 3)

    get account_positions_path(@account)
    assert_response :success
    assert_select "td", text: "SCTY"
    assert_select "td", text: "AAPL", count: 0
  end

  test "index leaves out snapshots the account has moved past" do
    Position.create!(account: @account, asset: @asset, as_of: @as_of - 1.day, units: 999)

    get positions_path
    assert_response :success
    assert_select "td", text: "999.0", count: 0
  end

  test "new renders the form" do
    get new_position_path
    assert_response :success
    assert_select "input[name=?]", "position[symbol]"
    # standardapi's create redirects to #show without this.
    assert_select "input[name=?][value=?]", "redirect_to", positions_path
  end

  test "the form's redirect returns to the list" do
    post positions_path, params: {
      redirect_to: positions_path,
      position: {account_id: @account.id, symbol: "TSLA", units: 4}
    }
    assert_redirected_to positions_path
  end

  test "create takes a symbol" do
    assert_difference "Position.count", 1 do
      post positions_path, params: {position: {
        account_id: @account.id, symbol: "TSLA", units: 4, price: 100.0
      }}
    end
    position = Position.order(:id).last
    assert_redirected_to position_path(position)
    assert_equal "TSLA", position.asset.symbol
    assert_equal @as_of, position.as_of
    assert_in_delta 400.0, position.value, 0.001
  end

  # A position on a derived account would be gone on the job's next run, so the
  # form never offers one.
  test "the account select lists only hand-maintained accounts" do
    derived = Account.create!(institution_name: "Fidelity", name: "Derived")

    get new_position_path
    assert_response :success
    assert_select "option[value=?]", @account.id.to_s
    assert_select "option[value=?]", derived.id.to_s, count: 0
  end

  test "creating for an account with no snapshot establishes one" do
    account = Account.create!(institution_name: "Vanguard", name: "IRA",
      positions_source: "manual")
    post positions_path, params: {position: {account_id: account.id, symbol: "VTI", units: 2}}

    position = Position.order(:id).last
    assert_equal position.as_of, account.reload.positions_as_of
    assert_equal [position], account.current_positions.to_a
  end

  test "edit renders the form and update persists" do
    get edit_position_path(@position)
    assert_response :success

    patch position_path(@position), params: {position: {units: 25}}
    @position.reload
    assert_in_delta 25, @position.units, 0.001
    assert_in_delta 500.0, @position.value, 0.001
  end

  test "destroy removes the position" do
    assert_difference "Position.count", -1 do
      delete position_path(@position)
    end
  end

  test "a derived account's positions offer no edit link" do
    @account.update!(positions_source: "transactions")

    get positions_path
    assert_response :success
    assert_select "a[href=?]", edit_position_path(@position), count: 0
  end

  test "a derived account's positions tab says where its holdings come from" do
    @account.update!(positions_source: "transactions")

    get account_positions_path(@account)
    assert_response :success
    assert_select "div", text: /Derived from this account's transactions/
    assert_select "input[name=?]", "position[symbol]", count: 0
  end

  test "a hand-maintained account's positions tab offers an add form" do
    get account_positions_path(@account)
    assert_response :success
    assert_select "div", text: /Entered and maintained by hand/
    assert_select "input[name=?]", "position[symbol]"
  end

  test "a manual position offers an edit link" do
    get positions_path
    assert_response :success
    assert_select "a[href=?]", edit_position_path(@position)
  end
end
