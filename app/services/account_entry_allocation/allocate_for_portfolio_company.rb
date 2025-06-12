module AccountEntryAllocation
  ############################################################
  # 11. AllocateForPortfolioCompany Operation
  #
  # This operation creates cumulative account entries for each
  # portfolio company related to a fund using a given fund formula.
  ############################################################
  class AllocateForPortfolioCompany < AllocationBaseOperation
    step :cumulate_account_entries

    # Main entry point: cumulates account entries for each portfolio company

    # Typical formula used would be like

    # fund.account_entries.for_aggregate_portfolio_investments.for_api_portfolio_company(portfolio_company.id).where(name: fund_formula.name).not_cumulative.where(reporting_date: @start_date..@end_date).sum(:amount_cents)

    # fund.account_entries.for_portfolio_investments.for_pi_portfolio_company(portfolio_company.id).where(name: fund_formula.name).not_cumulative.where(reporting_date: @start_date..@end_date).sum(:amount_cents)

    def cumulate_account_entries(ctx, for_folios:, **)
      fund_formula   = ctx[:fund_formula]
      end_date       = ctx[:end_date]
      start_date     = ctx[:start_date]
      fund           = ctx[:fund]
      bulk_records   = []
      allocation_run_id = ctx[:allocation_run_id]

      # Find all portfolio companies related to this fund through portfolio investments
      portfolio_companies = fund.entity.investors.joins(:portfolio_investments)
                                .where(portfolio_investments: { fund_id: fund.id })
                                .where(portfolio_investments: { investment_date: ..end_date })
                                .distinct

      account_entry_names = fund_formula.meta_data_hash["account_entry_names"]&.split(",")&.map(&:strip) if fund_formula.meta_data_hash.present?

      # For each portfolio company, generate cumulative entries
      portfolio_companies.each do |portfolio_company|
        Rails.logger.debug { "Cumulating #{fund_formula} to #{portfolio_company}" }

        # Determine the set of capital commitments to iterate over
        # If `for_folios` is true, use all commitments of the fund
        # Otherwise, treat as a single nil commitment (used in build_account_entry to signify no commitment)
        capital_commitments = for_folios ? fund.capital_commitments : [nil]

        # Iterate through each capital commitment
        capital_commitments.each do |capital_commitment|
          if account_entry_names.present?
            # If specific account entry names are provided,
            # build an account entry for each name (though `name` is not used in the method call)
            account_entry_names.each do |account_entry_name|
              build_account_entry(portfolio_company, capital_commitment, binding, ctx, account_entry_name)
            end
          else
            account_entry_name = fund_formula.name
            # If no specific names are provided, build a single account entry
            build_account_entry(portfolio_company, capital_commitment, binding, ctx, account_entry_name)
          end
        end
      end

      true
    end

    private

    # Creates a new AccountEntry instance for cumulative entry
    def build_account_entry(portfolio_company, capital_commitment, bdg, ctx, account_entry_name)
      fund = ctx[:fund]
      fund_formula = ctx[:fund_formula]
      end_date = ctx[:end_date]
      allocation_run_id = ctx[:allocation_run_id]

      ae = AccountEntry.new(
        fund_id: fund.id,
        entity_id: fund.entity_id,
        parent: portfolio_company,
        parent_name: portfolio_company.name,
        fund_formula: fund_formula,
        name: account_entry_name,
        entry_type: fund_formula.entry_type,
        reporting_date: end_date,
        cumulative: fund_formula.meta_data_hash["cumulative"] == "true",
        generated: true,
        rule_for: "reporting",
        allocation_run_id: allocation_run_id
      )

      begin
        create_instance_variables(ctx)
        AccountEntryAllocation::CreateAccountEntry.call(ctx.merge(account_entry: ae, capital_commitment: capital_commitment, parent: portfolio_company, bdg:))
      rescue StandardError => e
        raise "Error in #{fund_formula.name} for #{portfolio_company}: #{e.message}"
      end
    end
  end
end
