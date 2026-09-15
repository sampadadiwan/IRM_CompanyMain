module AccountEntryAllocation
  ############################################################
  # 7. AllocatePortfolioInvestments Operation
  ############################################################
  class AllocatePortfolioInvestments < AllocationBaseOperation
    step :allocate_portfolios_investment

    # The rule types this operation runs, with the options RunFormula passes for each.
    RULE_TYPE_OPTIONS = {
      "AllocatePortfolioInvestment" => { proforma: false, master_fund_investments: false },
      "AllocatePortfolioInvestment-Proforma" => { proforma: true, master_fund_investments: false },
      "AllocateMasterFundPortfolioInvestment" => { proforma: false, master_fund_investments: true },
      "AllocateMasterFundPortfolioInvestment-Proforma" => { proforma: true, master_fund_investments: true }
    }.freeze

    # The portfolio investments a formula allocates, as a relation. Shared with the post-run check
    # CheckHelpers#portfolio_allocations_tie, which must compare against exactly the investments the
    # formula was meant to allocate -- not every investment the fund holds.
    def self.portfolio_investments_for(fund, fund_formula, start_date:, end_date:, proforma: false, master_fund_investments: false)
      target_fund = if master_fund_investments
                      raise "Error in #{fund_formula.name}:#{fund_formula.id} Master fund for #{fund} is not set" if fund.master_fund.nil?

                      fund.master_fund
                    else
                      fund
                    end

      portfolio_investments = if proforma
                                # We only want to allocate proforma portfolio investments
                                target_fund.portfolio_investments.proforma
                              else
                                # We only want to allocate non-proforma portfolio investments (which are the actual investments and the default scope)
                                target_fund.portfolio_investments
                              end

      meta = fund_formula.meta_data_hash
      portfolio_investments = if meta.present? && meta["between_start_and_end_dates"] == "true"
                                # For some formulas, we only want to consider portfolio investments between the start and end dates. This is for performance reasons
                                portfolio_investments.where(investment_date: start_date..end_date)
                              else
                                # By default, we consider all portfolio investments up to the end date
                                portfolio_investments.where(investment_date: ..end_date)
                              end

      portfolio_investments = portfolio_investments.joins(:portfolio_company).where(meta["where"]) if meta.present? && meta["where"].present?
      portfolio_investments
    end

    def allocate_portfolios_investment(ctx, **)
      fund = ctx[:fund]
      commitment_cache = ctx[:commitment_cache]
      fund_formula = ctx[:fund_formula]
      start_date   = ctx[:start_date]
      end_date     = ctx[:end_date]
      sample       = ctx[:sample]
      user_id      = ctx[:user_id]

      Rails.logger.debug { "allocate_portfolios_investment(#{fund_formula.name})" }

      portfolio_investments = self.class.portfolio_investments_for(fund, fund_formula, start_date:, end_date:,
                                                                                       proforma: ctx[:proforma],
                                                                                       master_fund_investments: ctx[:master_fund_investments])

      # in some cases we want to use the investment date as the reporting date
      use_investment_date = fund_formula.meta_data_hash.present? && fund_formula.meta_data_hash["reporting_date"]&.strip == "investment_date"

      # Pre-load portfolio investments to avoid repeated queries in the loop
      portfolio_investments_array = portfolio_investments.includes(:fund, :investment_instrument, :portfolio_company).to_a

      ctx[:commitments].each.with_index do |capital_commitment, idx|
        commitment_cache.computed_fields_cache(capital_commitment, start_date, end_date)

        portfolio_investments_array.each do |portfolio_investment|
          # result = RubyProf.profile do
          reporting_date = if use_investment_date
                             portfolio_investment.investment_date
                           else
                             end_date
                           end
          ae = AccountEntrySqlite.new(
            name: fund_formula.name,
            entry_type: fund_formula.entry_type,
            entity_id: fund.entity_id,
            fund_id: fund.id,
            parent: portfolio_investment,
            parent_name: portfolio_investment.to_s[0..254],
            reporting_date: reporting_date,
            period: "As of #{reporting_date}",
            generated: true,
            fund_formula_id: fund_formula.id
          )

          begin
            create_instance_variables(ctx)
            AccountEntryAllocation::CreateAccountEntry.call(ctx.merge(account_entry: ae, capital_commitment: capital_commitment, parent: portfolio_investment, bdg: binding))
          rescue StandardError => e
            raise "Error in #{fund_formula.name}:#{fund_formula.id} for #{capital_commitment} #{portfolio_investment}: #{e.message}"
          end
        end

        # Move cache refresh outside the inner loop as it's redundant to refresh it for every portfolio investment
        # if the capital_commitment hasn't changed. CreateAccountEntry updates the cache internally.
        commitment_cache.computed_fields_cache(capital_commitment, start_date, end_date)

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 5).zero?
      end

      true
    end
  end
end
