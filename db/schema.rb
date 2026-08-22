# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_22_120200) do
  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "institution_name"
    t.string "name", null: false
    t.string "number"
    t.datetime "updated_at", null: false
  end

  create_table "assets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "exchange_id"
    t.string "name"
    t.datetime "splits_updated_at"
    t.string "symbol", null: false
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["exchange_id"], name: "index_assets_on_exchange_id"
    t.index ["symbol"], name: "index_assets_on_symbol", unique: true
  end

  create_table "exchanges", force: :cascade do |t|
    t.string "close_time"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "mic_code"
    t.string "name", null: false
    t.string "start_time"
    t.string "suffix"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_exchanges_on_code", unique: true
  end

  create_table "quotes", force: :cascade do |t|
    t.integer "asset_id"
    t.datetime "created_at", null: false
    t.float "price", null: false
    t.datetime "quoted_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_quotes_on_asset_id"
  end

  create_table "splits", force: :cascade do |t|
    t.integer "asset_id"
    t.datetime "created_at", null: false
    t.float "ratio"
    t.datetime "split_at"
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_splits_on_asset_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.float "adjusted_quantity"
    t.integer "asset_id", null: false
    t.datetime "created_at", null: false
    t.datetime "executed_at", null: false
    t.string "foreign_id"
    t.float "quantity"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.float "value"
    t.index ["account_id", "foreign_id"], name: "index_transactions_on_account_id_and_foreign_id", unique: true, where: "foreign_id IS NOT NULL"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["asset_id"], name: "index_transactions_on_asset_id"
  end

  add_foreign_key "assets", "exchanges"
  add_foreign_key "transactions", "accounts"
end
