require "test_helper"

class AccountTest < ActiveSupport::TestCase

  test "accounts derive their positions from transactions by default" do
    account = Account.create!(institution_name: "Robinhood", name: "Brokerage")
    assert_equal "transactions", account.positions_source
    assert account.derives_positions?
    assert_not account.manual_positions?
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
