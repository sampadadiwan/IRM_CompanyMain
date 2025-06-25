module AccountEntryAllocation
  ############################################################
  # 2. RunFormula Operation
  ############################################################
  class RunFormula < AllocationBaseOperation
    step :run_formula

    def run_formula(ctx, **)
      # Call the internal method to run the formula, at max 3 times if there is a failure
      (1..3).each do |attempt|
        run_formula_internal(ctx)
        return true
      rescue ActiveRecord::DatabaseConnectionError => e
        Rails.logger.error { "Attempt #{attempt} failed with error: #{e.message}" }
        Rails.logger.error { e.backtrace.join("\n") }
        if attempt == 3
          raise e # Re-raise the error after 3 attempts
        end

        Rails.logger.debug { "Retrying in #{2**attempt} seconds..." }
        sleep(2**attempt) # Exponential backoff before retrying
      end
      false # If all attempts fail, return false
    end

    def run_formula_internal(ctx, **)
      ctx[:fund]
      fund_formula = ctx[:fund_formula]
      ctx[:allocation_run_id]
      ctx[:bulk_insert_records] = []

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

      when "AllocateMasterFundAccountEntry-Name"
        AccountEntryAllocation::AllocateMasterFundAccountEntries.call(ctx.merge(name_or_entry_type: "name", grouped: true))
      when "AllocateMasterFundAccountEntry-EntryType"
        AccountEntryAllocation::AllocateMasterFundAccountEntries.call(ctx.merge(name_or_entry_type: "entry_type", grouped: true))
      when "AllocateMasterFundAccountEntryIndividual-Name"
        AccountEntryAllocation::AllocateMasterFundAccountEntries.call(ctx.merge(name_or_entry_type: "name", grouped: false))
      when "AllocateMasterFundAccountEntryIndividual-EntryType"
        AccountEntryAllocation::AllocateMasterFundAccountEntries.call(ctx.merge(name_or_entry_type: "entry_type", grouped: false))

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
      when "AllocateForPortfolioCompany"
        # Calculates a 'cumulative' value for each portfolio company at the fund level by aggregating amounts from account entries by matching the account entry name with the formula name
        AccountEntryAllocation::AllocateForPortfolioCompany.call(ctx.merge(for_folios: false))
      when "AllocateForPortfolioCompany-Folio"
        # Calculates a 'cumulative' value for each portfolio company at the folio level by aggregating amounts from account entries by matching the account entry name with the formula name
        AccountEntryAllocation::AllocateForPortfolioCompany.call(ctx.merge(for_folios: true))
      end

      # After the formula method sets up bulk_insert_records, do a bulk insert
      sub_ctx = ctx.merge(
        rollup_name: rollup_name,
        rollup_entry_type: rollup_entry_type
      )
      AccountEntryAllocation::BulkInsertData.call(sub_ctx)

      true
    end
  end
end
