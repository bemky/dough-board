require "test_helper"

class AmortizeLoanJobTest < ActiveSupport::TestCase

  TERMS = {
    "principal" => "300000",
    "annual_rate" => "6",
    "term_months" => "360",
    "started_on" => "2020-01-01"
  }.freeze

  setup do
    @account = Account.create!(institution_name: "Rocket", name: "Mortgage",
      positions_source: "amortized", loan_terms: TERMS)
  end

  def position
    @account.current_positions.first
  end

  # A debt is negative units of dollars at face value — the same shape the Plaid
  # connector writes, so a mortgage kept by hand and one synced from a lender
  # add up together rather than sitting in two lines.
  test "writes what's owed as a negative holding of dollars" do
    AmortizeLoanJob.perform_now(@account, as_of: Time.utc(2021, 1, 1))

    assert_equal "DEBT:HOME_LOAN", position.asset.symbol
    assert_equal "liability", position.asset.type
    assert_equal "Home Loan", position.asset.name
    assert_in_delta 1.0, position.price, 0.001
    assert_in_delta(-296_315.98, position.units, 0.01)
  end

  test "the account's value is what's owed, negated" do
    AmortizeLoanJob.perform_now(@account, as_of: Time.utc(2021, 1, 1))

    assert_in_delta(-296_315.98, @account.reload.value, 0.01)
  end

  # The same contract DerivePositionsJob keeps: an as_of appends a point, and
  # the balance can be asked for any date, so the history is a real paydown
  # curve rather than a series of guesses.
  test "each as_of appends a point, and the balance falls between them" do
    AmortizeLoanJob.perform_now(@account, as_of: Time.utc(2021, 1, 1))
    AmortizeLoanJob.perform_now(@account, as_of: Time.utc(2022, 1, 1))

    assert_equal 2, @account.positions.count
    owed = @account.positions.order(:as_of).map { |row| -row.units }
    assert_operator owed.last, :<, owed.first
    assert_equal Time.utc(2022, 1, 1), @account.reload.positions_as_of
  end

  test "with no as_of it corrects the current snapshot in place" do
    AmortizeLoanJob.perform_now(@account, as_of: Time.utc(2021, 1, 1))
    AmortizeLoanJob.perform_now(@account)

    assert_equal 1, @account.positions.count
    assert_equal Time.utc(2021, 1, 1), @account.reload.positions_as_of
  end

  test "a loan run to term is not a holding" do
    AmortizeLoanJob.perform_now(@account, as_of: Time.utc(2021, 1, 1))
    AmortizeLoanJob.perform_now(@account, as_of: Time.utc(2055, 1, 1))

    assert_empty @account.reload.current_positions
    assert_equal 0, @account.value
  end

  # It owns the whole snapshot, so anything else in it is stale by definition —
  # a position left behind by whatever wrote this account before.
  test "anything else in the snapshot is pruned" do
    stale = Asset.create!(symbol: "SCTY", type: "stock", splits_updated_at: Time.current)
    as_of = Time.utc(2021, 1, 1)
    Position.create!(account: @account, asset: stale, as_of: as_of, units: 10)

    AmortizeLoanJob.perform_now(@account, as_of: as_of)

    assert_equal ["DEBT:HOME_LOAN"], @account.current_positions.map { |row| row.asset.symbol }
  end

  test "an account whose positions come from somewhere else is left alone" do
    @account.update_columns(positions_source: "manual")

    AmortizeLoanJob.perform_now(@account, as_of: Time.utc(2021, 1, 1))

    assert_empty @account.positions
  end

  # Half-entered terms mean "no balance to report", not "paid off": writing a
  # zero would quietly wipe the last good number.
  test "terms that don't describe a loan write nothing" do
    @account.update_columns(loan_terms: {"principal" => "300000"})

    AmortizeLoanJob.perform_now(@account, as_of: Time.utc(2021, 1, 1))

    assert_empty @account.positions
    assert_nil @account.reload.positions_as_of
  end

  test "the kind of debt is the one the terms name" do
    @account.update!(loan_terms: TERMS.merge("debt_symbol" => "DEBT:AUTO_LOAN"))

    AmortizeLoanJob.perform_now(@account, as_of: Time.utc(2021, 1, 1))

    assert_equal "DEBT:AUTO_LOAN", position.asset.symbol
    assert_equal "Auto Loan", position.asset.name
  end

  # The asset is the kind of debt, not the account, so a second mortgage joins
  # the first in one portfolio line.
  test "two loans of a kind share one debt asset" do
    other = Account.create!(institution_name: "Chase", name: "Second Mortgage",
      positions_source: "amortized", loan_terms: TERMS.merge("principal" => "50000"))

    as_of = Time.utc(2021, 1, 1)
    AmortizeLoanJob.perform_now(@account, as_of: as_of)
    AmortizeLoanJob.perform_now(other, as_of: as_of)

    assert_equal 1, Asset.where(symbol: "DEBT:HOME_LOAN").count
    holdings = Position.where(as_of: as_of).portfolio
    assert_equal 1, holdings.length
    assert_in_delta(-345_702.0, holdings.first[:value], 5.0)
  end

end
