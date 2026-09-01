class BackfillAddToCommitmentCacheToFalse < ActiveRecord::Migration[8.1]
  # 20260829090000 only changed the column DEFAULT, which applies to new rows -- every
  # existing FundFormula kept the `true` backfilled by 20260109080228. That left the
  # memory fix half-applied on existing funds: AccountEntryAllocation::CommitmentCache
  # checks the flag first
  #
  #   return unless fund_formula.add_to_commitment_cache || @referenced_field_names.include?(field_name)
  #
  # so a flag of `true` short-circuits the dependency check and the field is cached
  # whether or not anything reads it. At the time of writing that was 1,158 of the
  # enabled flagged formulas producing a field no other formula in their fund ever
  # reads -- held per-commitment for the whole run, and never evicted either (only
  # referenced fields appear in last_consumer_index).
  #
  # Flipping these to false hands the decision to the per-run dependency scan in
  # RunFormulas#configure_commitment_cache_dependencies, which reads every in-scope
  # formula's source before the first one runs, so anything genuinely read downstream
  # is still cached. The flag remains as a manual override for what that scan can't
  # see -- a field reached dynamically rather than written literally as @name.
  #
  # Verified safe against the current corpus: that dynamic case needs
  # instance_variable_get (Ruby has no `@#{name}` syntax), which appears in 0 of the
  # 2,199 formulas. The runtime-built formulas don't introduce one either --
  # FundFormula#formula_for_entry_name substitutes a string literal, and the
  # Quarterly/YTD/Since Inception formulas in CreateAccountEntry reference a local
  # plus the always-set @start_date/@end_date.
  def up
    FundFormula.unscoped.update_all(add_to_commitment_cache: false)
  end

  # Restores the pre-migration state (20260109080228 had set every row to true).
  def down
    FundFormula.unscoped.update_all(add_to_commitment_cache: true)
  end
end
