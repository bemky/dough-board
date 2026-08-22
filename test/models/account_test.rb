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

end
