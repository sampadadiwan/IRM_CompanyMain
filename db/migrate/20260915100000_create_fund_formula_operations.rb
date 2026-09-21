# Background operations on a fund's formulas that support previews and then applies from the fund
# formulas page (openspec/changes/incremental-allocation-ui):
#   enable_incremental / disable_incremental  switch a fund onto or off incremental allocation
#   reseed_carry_forward                      recompute tracking formulas' stored starting values
#   suggest_checks                            generate pre/post-run check formulas for the fund
#
# One row per request, kept after apply, refusal or failure, so it is also the history of who changed
# which fund. plan holds the preview (or the suggestion set, which cannot be regenerated identically
# when AI was used), result what apply did, params the request's inputs (e.g. a reseed date).
class CreateFundFormulaOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :fund_formula_operations do |t|
      t.bigint :entity_id, null: false
      t.bigint :fund_id, null: false
      t.string :operation, limit: 30, null: false
      t.string :status, limit: 20, null: false, default: "previewing"
      t.bigint :requested_by_id, null: false
      t.bigint :applied_by_id
      t.json :params
      t.json :plan
      t.json :result
      t.text :error
      t.datetime :previewed_at
      t.datetime :applied_at
      t.timestamps
    end
    change_table :fund_formula_operations, bulk: true do |t|
      t.index %i[fund_id created_at]
      t.index :entity_id
      t.index :status
    end
  end
end
