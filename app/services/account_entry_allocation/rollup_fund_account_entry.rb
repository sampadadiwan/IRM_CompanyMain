module AccountEntryAllocation
  ############################################################
  # 10. RollupAsFundAccountEntry Operation
  ############################################################
  class RollupAsFundAccountEntry < AllocationBaseOperation
    step :rollup_as_fund_account_entry

    def rollup_as_fund_account_entry(ctx, **)
      fund         = ctx[:fund]
      fund_formula = ctx[:fund_formula]
      end_date     = ctx[:end_date]
      start_date   = ctx[:start_date]

      # Destroy old fund-level entries
      fund.fund_account_entries.where(
        name: fund_formula.name,
        entity_id: fund.entity_id,
        fund: fund,
        reporting_date: end_date,
        entry_type: fund_formula.entry_type,
        generated: true,
        capital_commitment_id: nil
      ).find_each(&:destroy)

      account_entries = fund.account_entries
                            .where(
                              name: fund_formula.name,
                              entity_id: fund.entity_id,
                              fund: fund,
                              entry_type: fund_formula.entry_type,
                              generated: true,
                              cumulative: false
                            ).where(reporting_date: start_date..end_date)

      sum_cents = account_entries.sum(:amount_cents)
      fund.fund_account_entries.create!(
        name: fund_formula.name,
        entity_id: fund.entity_id,
        fund: fund,
        reporting_date: end_date,
        entry_type: fund_formula.entry_type,
        generated: true,
        cumulative: true,
        commitment_type: fund_formula.commitment_type,
        amount_cents: sum_cents
      )

      true
    end
  end
end
