class DefaultAddToCommitmentCacheToFalse < ActiveRecord::Migration[8.1]
  def change
    # Only changes the default applied to new rows. Existing FundFormulas keep
    # whatever value they already have (all true, from the original backfill in
    # 20260109080228_add_commitment_cache_to_fund_formula.rb). Caching correctness
    # no longer depends on this flag alone -- AccountEntryAllocation::CommitmentCache
    # also caches a field whenever some later formula's source actually reads it
    # (FundFormula#referenced_field_names), so a new formula that needs to be read
    # downstream is still cached even with this flag left off.
    change_column_default :fund_formulas, :add_to_commitment_cache, from: true, to: false
  end
end
