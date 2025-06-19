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

      # Rollup the fund-level entries, by default its only the fund formula name
      rollups_for_name = [fund_formula.name]
      if fund_formula.generate_ytd_qtly
        # Add the YTD and Quarterly rollups
        AccountEntryAllocation::CreateAccountEntry::ADDITONAL_AE.each do |ae_name|
          rollups_for_name << ("#{ae_name} #{fund_formula.name}")
        end
      end

      # Generate the fund-level entries for each of the names
      rollups_for_name.each do |name|
        generate_fund_rollup(ctx, name, fund, fund_formula, start_date, end_date)
      end

      true
    end

    def generate_fund_rollup(ctx, name, fund, fund_formula, start_date, end_date)
      # Destroy old fund-level entries
      fund.fund_account_entries.where(
        name: name,
        entity_id: fund.entity_id,
        fund: fund,
        reporting_date: end_date,
        entry_type: fund_formula.entry_type,
        generated: true,
        capital_commitment_id: nil
      ).find_each(&:destroy)

      account_entries = fund.account_entries
                            .where(
                              name: name,
                              entity_id: fund.entity_id,
                              fund: fund,
                              entry_type: fund_formula.entry_type,
                              generated: true,
                              cumulative: false
                            ).where(reporting_date: start_date..end_date)

      sum_cents = account_entries.sum(:amount_cents)
      fund.fund_account_entries.create!(
        name: name,
        entity_id: fund.entity_id,
        fund: fund,
        reporting_date: end_date,
        entry_type: fund_formula.entry_type,
        generated: true,
        cumulative: true,
        fund_formula: fund_formula,
        # Since this is a rollup, the rule_for is reporting
        rule_for: :reporting,
        amount_cents: sum_cents,
        allocation_run_id: ctx[:allocation_run_id]
      )
    end
  end
end
