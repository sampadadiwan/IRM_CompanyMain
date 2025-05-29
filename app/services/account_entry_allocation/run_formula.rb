module AccountEntryAllocation
  ############################################################
  # 2. RunFormula Operation
  ############################################################
  class RunFormula < AllocationBaseOperation
    step :run_formula

    def run_formula(ctx, **)
      fund               = ctx[:fund]
      fund_formula       = ctx[:fund_formula]
      ctx[:bulk_insert_records] = []

      existing_record_count = fund.account_entries.generated.count

      # Decide the "rollup name" and "rollup entry type"
      rollup_name = fund_formula.name
      rollup_entry_type = fund_formula.entry_type

      Rails.logger.debug { "Running formula #{fund_formula.to_json}" }

      # Run sub-operations based on rule_type
      case fund_formula.rule_type
      when "GenerateCustomField"
        AccountEntryAllocation::GenerateCustomFields.call(ctx)
      when "AllocateAccountEntry", "AllocateAccountEntry-Name"
        AccountEntryAllocation::AllocateAccountEntries.call(ctx.merge(name_or_entry_type: "name", grouped: true))
      when "AllocateAccountEntryIndividual-Name"
        AccountEntryAllocation::AllocateAccountEntries.call(ctx.merge(name_or_entry_type: "name", grouped: false))
      when "AllocateAccountEntry-EntryType"
        AccountEntryAllocation::AllocateAccountEntries.call(ctx.merge(name_or_entry_type: "entry_type", grouped: true))
      when "AllocateAccountEntryIndividual-EntryType"
        AccountEntryAllocation::AllocateAccountEntries.call(ctx.merge(name_or_entry_type: "entry_type", grouped: false))
      when "AllocateMasterFundAccountEntry"
        AccountEntryAllocation::AllocateMasterFundAccountEntries.call(ctx.merge(name_or_entry_type: "name"))
      when "CumulateAccountEntry"
        AccountEntryAllocation::CumulateAccountEntries.call(ctx)
      when "GenerateAccountEntry"
        AccountEntryAllocation::GenerateAccountEntries.call(ctx)
      when "AllocateAggregatePortfolios"
        AccountEntryAllocation::AllocateAggregatePortfolios.call(ctx)
      when "AllocatePortfolioInvestment"
        AccountEntryAllocation::AllocatePortfolioInvestments.call(ctx)
        # For portfolio investments, override the rollup name
        rollup_name = nil
        rollup_entry_type = fund_formula.name
      when "Percentage"
        AccountEntryAllocation::ComputeCustomPercentage.call(ctx)
      when "GeneratePortfolioNumbersForFund"
        AccountEntryAllocation::GeneratePortfolioNumbersForFund.call(ctx)
      when "CumulateForPortfolioCompany"
        AccountEntryAllocation::CumulateForPortfolioCompany.call(ctx.merge(for_folios: false))
      when "CumulateForPortfolioCompany-Folio"
        AccountEntryAllocation::CumulateForPortfolioCompany.call(ctx.merge(for_folios: true))
      end

      # After the formula method sets up bulk_insert_records, do a bulk insert
      sub_ctx = ctx.merge(
        existing_record_count: existing_record_count,
        rollup_name: rollup_name,
        rollup_entry_type: rollup_entry_type
      )
      AccountEntryAllocation::BulkInsertData.call(sub_ctx)

      true
    end
  end
end
