class MakeCapitalRemittanceCommitmentRequired < ActiveRecord::Migration[8.1]
  # A capital remittance is always the draw-down of one capital commitment: CapitalRemittance
  # `belongs_to :capital_commitment` without `optional: true`, so the model already refuses to
  # save one without it. The column was left nullable when it was added, which only matters
  # when validations are bypassed (`save(validate: false)`, `update_columns`, raw imports) --
  # exactly how the rule-engine Cucumber fixtures used to create commitment-less remittances,
  # which then crashed CapitalCallRuleContextProvider. Enforce the invariant in the database
  # so no code path, validated or not, can create one.

  def up
    # Fail loudly rather than let ALTER TABLE fail half-way through: a legacy row with no
    # commitment needs a human decision (attach or delete), not a migration.
    orphans = CapitalRemittance.unscoped.where(capital_commitment_id: nil).count
    raise "#{orphans} capital_remittances row(s) have no capital_commitment_id; fix them before adding NOT NULL" if orphans.positive?

    change_column_null :capital_remittances, :capital_commitment_id, false
  end

  def down
    change_column_null :capital_remittances, :capital_commitment_id, true
  end
end
