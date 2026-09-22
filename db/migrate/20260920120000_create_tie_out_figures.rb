# The fund's own figure for one number, typed in while reviewing an allocation run — see
# docs/modules/allocation/allocation_run_review_proposals.md (proposals 2 and 3).
#
# Deliberately keyed to (fund, date, folio, name) and NOT to the allocation run: re-running a
# period creates a new AllocationRun and hard-deletes the previous attempt's entries
# (RunFormulas#delete_existing_primary_entries), so figures tied to a run would have to be
# retyped after every re-run. The fund's own numbers belong to the period, not to our attempt
# at it.
#
# capital_commitment_id NULL means a fund total (the totals sheet); a folio id means one
# investor's figure (the folio check), which reuses this table without a migration.
class CreateTieOutFigures < ActiveRecord::Migration[8.1]
  def change
    create_table :tie_out_figures do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      # NULL = the fund total for this name. Set = one folio's figure.
      t.references :capital_commitment, null: true, foreign_key: true
      # The allocation run's end_date — the date the figure is "as of".
      t.date :as_of_date, null: false
      # Matches account_entries.name / .entry_type, and their column widths.
      t.string :name, limit: 125, null: false
      t.string :entry_type, limit: 60
      # Same precision as account_entries.amount_cents so a difference is exact.
      t.decimal :amount_cents, precision: 30, scale: 8, null: false, default: 0
      # Who last typed it — this is evidence of a review, so it is worth knowing.
      t.references :user, null: false, foreign_key: true
      t.text :notes
      t.timestamps
    end

    # The lookup the totals sheet does: every figure for one fund and date, in one query.
    # Not unique: MySQL treats NULL capital_commitment_ids as distinct, so a unique index
    # would not hold for fund totals anyway. Uniqueness is enforced in the model instead.
    add_index :tie_out_figures, %i[fund_id as_of_date capital_commitment_id name],
              name: "idx_tie_out_figures_lookup"
  end
end
