require "test_helper"

class TransactionsControllerImportTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    @account = Account.create!(provider: "Robinhood", name: "Import Test")
    # Pre-create the assets with freshly-cached splits so Transaction#save does
    # not hit the network (load_splits short-circuits when splits_updated_at is
    # recent; quotes are only fetched when reading price, not on save).
    %w[SCTY TSLA].each do |sym|
      Asset.create!(symbol: sym, splits_updated_at: Time.current)
    end
  end

  # Two equity rows + one option row (which must be skipped).
  CSV_BODY = <<~CSV
    fill_date,symbol,asset_type,side,quantity,avg_price,gross_amount,fees,net_cash,order_type,source,order_id
    2015-03-18,SCTY,equity,buy,10,49.71,497.10,0,-497.10,market,user,order-scty
    2020-01-02,TSLA,equity,sell,2,195.16,390.34,0,390.34,market,user,order-tsla
    2020-12-28,ABNB 75P 2023-01-20,option,buy_to_open,1,16.30,1630.00,0,-1630.00,limit,user,order-opt
  CSV

  # Same columns, but no order_id on either row.
  CSV_WITHOUT_IDS = <<~CSV
    fill_date,symbol,asset_type,side,quantity,avg_price,gross_amount,fees,net_cash,order_type,source,order_id
    2015-03-18,SCTY,equity,buy,10,49.71,497.10,0,-497.10,market,user,
    2020-01-02,TSLA,equity,sell,2,195.16,390.34,0,390.34,market,user,
  CSV

  def upload(body = CSV_BODY)
    file = Tempfile.new(["trades", ".csv"])
    file.write(body)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv")
  end

  test "imports equity rows, skips options, maps columns and dedups" do
    assert_difference "Transaction.count", 2 do
      post import_transactions_path, params: {account_id: @account.id, file: upload}
    end
    assert_redirected_to root_path

    buy = Transaction.find_by(foreign_id: "order-scty")
    assert_equal "buy", buy.type
    assert_equal @account.id, buy.account_id
    assert_equal "SCTY", buy.asset.symbol
    assert_in_delta 497.10, buy.value, 0.001
    assert_equal Date.new(2015, 3, 18), buy.executed_at.to_date

    sale = Transaction.find_by(foreign_id: "order-tsla")
    assert_equal "sale", sale.type # sell -> sale

    # Re-import: no new rows created (dedup on account_id + foreign_id).
    assert_no_difference "Transaction.count" do
      post import_transactions_path, params: {account_id: @account.id, file: upload}
    end
  end

  test "rows without an order_id always create, never match an existing null" do
    existing = Transaction.create!(account: @account, asset: Asset.find_by(symbol: "SCTY"),
      type: "buy", executed_at: "2020-01-01", quantity: 1, value: 100)
    assert_nil existing.foreign_id

    # Both ID-less rows create their own record, and neither touches `existing`.
    assert_difference "Transaction.count", 2 do
      post import_transactions_path, params: {account_id: @account.id, file: upload(CSV_WITHOUT_IDS)}
    end
    assert_equal 1, existing.reload.quantity

    # Re-importing the same file duplicates, since there is no id to dedup on.
    assert_difference "Transaction.count", 2 do
      post import_transactions_path, params: {account_id: @account.id, file: upload(CSV_WITHOUT_IDS)}
    end
  end

  test "edit action renders the form and update persists foreign_id" do
    asset = Asset.find_by(symbol: "SCTY")
    txn = Transaction.create!(account: @account, asset: asset, type: "buy",
      executed_at: "2020-01-01", quantity: 1, value: 100, foreign_id: "old-id")

    get edit_transaction_path(txn)
    assert_response :success
    assert_select "input[name=?][value=?]", "transaction[foreign_id]", "old-id"

    patch transaction_path(txn), params: {transaction: {foreign_id: "new-id"}}
    assert_equal "new-id", txn.reload.foreign_id
  end

  test "rejects import without account or file" do
    post import_transactions_path, params: {file: upload}
    assert_redirected_to root_path
    assert_equal "Choose an account and a CSV file to import.", flash[:alert]
  end
end
