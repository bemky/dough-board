require "application_system_test_case"

class SymbolFilterTest < ApplicationSystemTestCase
  setup do
    sign_in
    t = Time.current
    Asset.insert_all([{symbol: "ZZZ", created_at: t, updated_at: t}, {symbol: "AAA", created_at: t, updated_at: t}])
    account = Account.create!(name: "Test", institution_name: "P")
    Transaction.insert_all(Asset.where(symbol: %w[AAA ZZZ]).map { |asset|
      {account_id: account.id, asset_id: asset.id, type: "buy", quantity: 1, adjusted_quantity: 1,
       value: 10, executed_at: t, created_at: t, updated_at: t}
    })
  end

  test "filtering transactions by symbol via the dropdown" do
    visit transactions_path
    assert_selector "tbody tr", count: 2

    find("[data-filter-button]").click
    within "komp-dropdown" do
      check "AAA"
      click_button "Apply"
    end

    assert_selector "tbody tr", count: 1
    assert_text "AAA"
    assert_no_text "ZZZ"

    # Sorting keeps the filter, and the button reflects the active filter count.
    find("[data-filter-button]").click
    within("komp-dropdown") { assert_checked_field "AAA" }
  end
end
