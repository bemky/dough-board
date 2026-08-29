require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in
    @account = Account.create!(institution_name: "Robinhood", name: "Brokerage")
    @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
    Quote.create!(asset: @asset, price: 20.0, quoted_at: Time.current)

    @as_of = Time.current.change(usec: 0)
    Position.create!(account: @account, asset: @asset, as_of: @as_of, units: 10, price: 20.0)
    @account.update!(positions_as_of: @as_of)
  end

  TERMS = {
    principal: "300000",
    annual_rate: "6",
    term_months: "360",
    started_on: "2020-01-01"
  }.freeze

  test "a loan can be entered on the account form" do
    get new_account_path
    assert_response :success
    assert_select "select[name=?]", "account[loan_terms][debt_symbol]"
    assert_select "input[name=?]", "account[loan_terms][principal]"
    assert_select "input[name=?]", "account[loan_terms][term_months]"
  end

  test "creating an amortized account records the loan and its balance" do
    perform_enqueued_jobs do
      post accounts_path, params: {account: {
        name: "Mortgage", institution_name: "Rocket",
        positions_source: "amortized", loan_terms: TERMS
      }, redirect_to: accounts_path}
    end
    assert_redirected_to accounts_path

    account = Account.find_by(name: "Mortgage")
    assert_equal "amortized", account.positions_source
    assert_equal "300000", account.loan_terms["principal"]
    assert_operator account.value, :<, 0, "a loan is a negative holding"
  end

  # loan_terms is a json column; permitting it wholesale would let a form post
  # write arbitrary JSON onto an account.
  test "keys the calculation doesn't read are kept out of loan_terms" do
    post accounts_path, params: {account: {
      name: "Mortgage", institution_name: "Rocket",
      positions_source: "amortized", loan_terms: TERMS.merge(whatever: "no")
    }, redirect_to: accounts_path}

    account = Account.find_by(name: "Mortgage")
    assert_equal %w(annual_rate principal started_on term_months), account.loan_terms.keys.sort
  end

  test "the account page shows the terms behind the balance" do
    account = Account.create!(institution_name: "Rocket", name: "Mortgage",
      positions_source: "amortized", loan_terms: TERMS.stringify_keys)

    get account_path(account)
    assert_response :success
    assert_select "dd", text: "$1,798.65"
  end

  test "a demo scales the terms too, so the mortgage isn't on the page beside them" do
    account = Account.create!(institution_name: "Rocket", name: "Mortgage",
      positions_source: "amortized", loan_terms: TERMS.stringify_keys)

    post demo_path
    get account_path(account)

    assert_response :success
    assert_select "dd", text: "$1,798.65", count: 0
    assert_select "dd", text: "$300,000.00", count: 0
    # The rate is not a quantity, and a demo that changed it would be a demo of
    # a different loan.
    assert_select "dd", text: "6%"
  end

  test "index values accounts from their current positions" do
    get accounts_path
    assert_response :success
    assert_select "td", text: "$200.00"
  end

  test "index nets a debt account against the rest, and names what it is" do
    card = Account.create!(institution_name: "Testbank", name: "Card", positions_source: "connection")
    debt = Asset.create!(symbol: "DEBT:CREDIT_CARD", name: "Credit Card Debt",
      type: "liability", splits_updated_at: Time.current)
    Position.create!(account: card, asset: debt, as_of: @as_of, units: -50.0, price: 1.0)
    card.update!(positions_as_of: @as_of)

    get accounts_path
    assert_response :success
    # A debt has no area to tile, so it's said in words instead.
    assert_select "div", text: /After \$50\.00 owed on/
    assert_select "div", text: /\$150\.00/
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
