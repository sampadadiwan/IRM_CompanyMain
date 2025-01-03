class CreateDistributionFees < ActiveRecord::Migration[7.2]
  def change
    create_table "distribution_fees", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
      t.string "name", limit: 50
      t.date "start_date"
      t.date "end_date"
      t.string "notes"
      t.bigint "entity_id", null: false
      t.bigint "fund_id", null: false
      t.bigint "capital_distribution_id", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.boolean "formula", default: false
      t.index ["capital_distribution_id"], name: "index_distribution_fees_on_capital_distribution_id"
      t.index ["entity_id"], name: "index_distribution_fees_on_entity_id"
      t.index ["fund_id"], name: "index_distribution_fees_on_fund_id"
    end
  end
end
