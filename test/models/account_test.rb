require "test_helper"

class AccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper


  test "accounts derive their positions from transactions by default" do
    account = Account.create!(institution_name: "Robinhood", name: "Brokerage")
    assert_equal "transactions", account.positions_source
    assert account.derives_positions?
    assert_not account.manual_positions?
  end

  TERMS = {
    "principal" => "300000",
    "annual_rate" => "6",
    "term_months" => "360",
    "started_on" => "2020-01-01"
  }.freeze

  test "an amortized account works its balance out from its terms" do
    account = Account.create!(institution_name: "Rocket", name: "Mortgage",
      positions_source: "amortized", loan_terms: TERMS)

    assert account.amortized_positions?
    assert_not account.derives_positions?, "the transactions fold must leave it alone"
    assert_not account.manual_positions?, "its positions are not editable by hand"
    assert_in_delta 1798.65, account.amortization.monthly_payment, 0.01
  end

  # Accepting them would leave an account reporting no balance at all, which
  # reads as a mortgage that's been paid off.
  test "an amortized account refuses terms that don't describe a loan" do
    account = Account.new(institution_name: "Rocket", name: "Mortgage",
      positions_source: "amortized", loan_terms: TERMS.merge("term_months" => "0"))

    assert_not account.valid?
    assert_not_empty account.errors[:loan_terms]
  end

  test "every other account ignores loan terms entirely" do
    account = Account.new(institution_name: "Robinhood", name: "Brokerage",
      loan_terms: {"principal" => "nonsense"})

    assert account.valid?
    assert_nil account.amortization
  end

  # The balance follows from the terms, so a change to them is a change to the
  # holding — waiting for the hourly run would leave the account wrong.
  test "changing the terms recomputes the balance now" do
    account = Account.create!(institution_name: "Rocket", name: "Mortgage",
      positions_source: "transactions")

    assert_enqueued_with job: AmortizeLoanJob, args: [account] do
      account.update!(positions_source: "amortized", loan_terms: TERMS)
    end

    assert_enqueued_with job: AmortizeLoanJob, args: [account] do
      account.update!(loan_terms: TERMS.merge("principal" => "250000"))
    end
  end

  # The job writes positions_as_of, which would otherwise queue another run of
  # the job that just wrote it.
  test "an unrelated save on an amortized account queues nothing" do
    account = Account.create!(institution_name: "Rocket", name: "Mortgage",
      positions_source: "amortized", loan_terms: TERMS)

    assert_no_enqueued_jobs only: AmortizeLoanJob do
      account.update!(positions_as_of: Time.current, name: "Home Loan")
    end
  end

  test "a debt kind outside the vocabulary falls back rather than inventing an asset" do
    account = Account.new(loan_terms: TERMS.merge("debt_symbol" => "DEBT:HOVERCRAFT"))
    assert_equal "DEBT:HOME_LOAN", account.debt_symbol

    account.loan_terms = TERMS.merge("debt_symbol" => "DEBT:STUDENT_LOAN")
    assert_equal "DEBT:STUDENT_LOAN", account.debt_symbol
  end

  test "positions_source is constrained" do
    account = Account.new(name: "Brokerage", positions_source: "vibes")
    assert_not account.valid?
    assert_includes account.errors[:positions_source], "is not included in the list"
  end

  test "current_positions is empty until something takes a snapshot" do
    account = Account.create!(institution_name: "Robinhood", name: "Brokerage")
    asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
    Position.create!(account: account, asset: asset, as_of: 1.day.ago, units: 5)

    account.update_column(:positions_as_of, nil)
    assert_empty account.reload.current_positions
    assert_equal 0, account.value
  end

  class DestroyTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @account = Account.create!(institution_name: "Robinhood", name: "Brokerage")
      @asset = Asset.create!(symbol: "SCTY", splits_updated_at: Time.current)
      @transaction = Transaction.create!(account: @account, asset: @asset, type: "buy",
        executed_at: Date.new(2020, 1, 1), quantity: 10, value: 100)
      Position.create!(account: @account, asset: @asset, units: 10)
    end

    # transactions.account_id has a foreign key, so without a dependent option
    # the database refuses the delete rather than Rails cleaning up first.
    test "destroying an account takes its transactions and positions with it" do
      assert_difference ["Transaction.count", "Position.count"], -1 do
        assert_difference "Account.count", -1 do
          @account.destroy
        end
      end
    end

    test "the assets stay, since other accounts hold them too" do
      assert_no_difference "Asset.count" do
        @account.destroy
      end
    end

    # destroy_all would fire after_commit on every row — thousands of them for a
    # real account — each enqueueing a derive for the account being deleted.
    test "destroying an account queues no derivation for it" do
      assert_no_enqueued_jobs only: DerivePositionsJob do
        @account.destroy
      end
    end
  end

end
