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

ActiveRecord::Schema[7.1].define(version: 2024_01_30_230345) do
  create_table "assets", force: :cascade do |t|
    t.string "name"
    t.string "symbol", null: false
    t.string "exchange"
    t.string "type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "splits_updated_at"
  end

  create_table "quotes", force: :cascade do |t|
    t.integer "asset_id"
    t.float "price", null: false
    t.datetime "quoted_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_quotes_on_asset_id"
  end

  create_table "splits", force: :cascade do |t|
    t.integer "asset_id"
    t.float "ratio"
    t.datetime "split_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_splits_on_asset_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "asset_id", null: false
    t.string "type", null: false
    t.datetime "executed_at", null: false
    t.string "vendor"
    t.float "quantity"
    t.float "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "adjusted_quantity"
    t.index ["asset_id"], name: "index_transactions_on_asset_id"
  end

end
