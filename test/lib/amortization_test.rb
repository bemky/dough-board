require "test_helper"

class AmortizationTest < ActiveSupport::TestCase

  # A 30-year fixed at 6% on $300,000 — the textbook case, and one whose payment
  # every mortgage calculator agrees on.
  def loan(overrides = {})
    Amortization.from({
      "principal" => "300000",
      "annual_rate" => "6",
      "term_months" => "360",
      "started_on" => "2020-01-01"
    }.merge(overrides))
  end

  test "the monthly payment matches the standard amortization formula" do
    assert_in_delta 1798.65, loan.monthly_payment, 0.01
  end

  test "nothing is owed before the first payment, and the whole principal stands" do
    assert_equal 0, loan.payments_made(on: Date.new(2020, 1, 15))
    assert_in_delta 300_000, loan.balance(on: Date.new(2020, 1, 15)), 0.01
  end

  # The first payment on a 6% loan is $1,500 interest and $298.65 principal —
  # which is the whole point of an amortization schedule.
  test "the first payment is almost all interest" do
    assert_equal 1, loan.payments_made(on: Date.new(2020, 2, 1))
    assert_in_delta 300_000 - 298.65, loan.balance(on: Date.new(2020, 2, 1)), 0.05
  end

  test "the balance falls faster the further in you are" do
    first_year = loan.balance(on: Date.new(2020, 1, 1)) - loan.balance(on: Date.new(2021, 1, 1))
    last_year = loan.balance(on: Date.new(2049, 1, 1)) - loan.balance(on: Date.new(2050, 1, 1))
    assert_operator last_year, :>, first_year * 3
  end

  test "the loan is paid off at the end of its term, and stays paid off" do
    assert_equal 360, loan.payments_made(on: Date.new(2050, 1, 1))
    assert_in_delta 0, loan.balance(on: Date.new(2050, 1, 1)), 0.01
    # Past the term, payments stop counting rather than going negative.
    assert_equal 360, loan.payments_made(on: Date.new(2060, 1, 1))
    assert_in_delta 0, loan.balance(on: Date.new(2060, 1, 1)), 0.01
  end

  test "a payment is not made until its day of the month comes round" do
    assert_equal 11, loan.payments_made(on: Date.new(2020, 12, 31))
    assert_equal 12, loan.payments_made(on: Date.new(2021, 1, 1))
  end

  # Dividing by the rate is the usual way to write this, and it blows up at zero.
  test "an interest-free loan divides rather than amortizes" do
    interest_free = loan("annual_rate" => "0", "principal" => "12000", "term_months" => "12")

    assert_in_delta 1000, interest_free.monthly_payment, 0.01
    assert_in_delta 9000, interest_free.balance(on: Date.new(2020, 4, 1)), 0.01
    assert_in_delta 0, interest_free.balance(on: Date.new(2021, 1, 1)), 0.01
    assert_in_delta 0, interest_free.total_interest, 0.01
  end

  test "reports what the loan costs and when it ends" do
    assert_equal Date.new(2050, 1, 1), loan.payoff_on
    assert_in_delta 347_514.0, loan.total_interest, 1.0
  end

  # nil is the contract for "these terms don't describe a loan" — the account
  # validation and the job both read it that way.
  test "terms that don't describe a loan build nothing" do
    assert_nil Amortization.from(nil)
    assert_nil Amortization.from({})
    assert_nil loan("principal" => "0")
    assert_nil loan("principal" => "-5000")
    assert_nil loan("term_months" => "0")
    assert_nil loan("term_months" => "1200")
    assert_nil loan("annual_rate" => "-1")
    assert_nil loan("annual_rate" => "100")
    assert_nil loan("started_on" => "")
    assert_nil loan("started_on" => "whenever")
  end

  test "takes symbol keys as readily as the string keys the column returns" do
    from_symbols = Amortization.from(principal: 300_000, annual_rate: 6, term_months: 360,
      started_on: Date.new(2020, 1, 1))
    assert_in_delta 1798.65, from_symbols.monthly_payment, 0.01
  end

end
