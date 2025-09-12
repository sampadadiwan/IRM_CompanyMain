module AccountEntryAllocation
  ############################################################
  # 7. AllocatePortfolioInvestments Operation
  ############################################################
  class AllocatePortfolioInvestments < AllocationBaseOperation
    step :allocate_portfolios_investment

    def allocate_portfolios_investment(ctx, **)
      fund = ctx[:fund]
      commitment_cache = ctx[:commitment_cache]
      fund_formula = ctx[:fund_formula]
      start_date   = ctx[:start_date]
      end_date     = ctx[:end_date]
      sample       = ctx[:sample]
      user_id      = ctx[:user_id]

      Rails.logger.debug { "allocate_portfolios_investment(#{fund_formula.name})" }

      target_fund = if ctx[:master_fund_investments]
                      raise "Error in #{fund_formula.name}: Master fund for #{fund} is not set" if fund.master_fund.nil?

                      fund.master_fund
                    else
                      fund
                    end

      portfolio_investments = if ctx[:proforma]
                                # We only want to allocate proforma portfolio investments
                                target_fund.portfolio_investments.proforma
                              else
                                # We only want to allocate non-proforma portfolio investments (which are the actual investments and the default scope)
                                target_fund.portfolio_investments
                              end

      portfolio_investments = if fund_formula.meta_data_hash.present? && fund_formula.meta_data_hash["between_start_and_end_dates"] == "true"
                                # For some formulas, we only want to consider portfolio investments between the start and end dates. This is for performance reasons
                                portfolio_investments.where(investment_date: start_date..end_date)
                              else
                                # By default, we consider all portfolio investments up to the end date
                                portfolio_investments.where(investment_date: ..end_date)
                              end

      fund_formula.commitments(end_date, sample).includes(:entity, :fund, :investor_kyc).each_with_index do |capital_commitment, idx|
        commitment_cache.computed_fields_cache(capital_commitment, start_date)

        portfolio_investments.each do |portfolio_investment|
          # result = RubyProf.profile do

          ae = AccountEntry.new(
            name: fund_formula.name,
            entry_type: fund_formula.entry_type,
            entity_id: fund.entity_id,
            fund: fund,
            parent: portfolio_investment,
            reporting_date: end_date,
            period: "As of #{end_date}",
            generated: true,
            fund_formula: fund_formula
          )

          begin
            create_instance_variables(ctx)
            AccountEntryAllocation::CreateAccountEntry.call(ctx.merge(account_entry: ae, capital_commitment: capital_commitment, parent: portfolio_investment, bdg: binding))
          rescue StandardError => e
            raise "Error in #{fund_formula.name} for #{capital_commitment} #{portfolio_investment}: #{e.message}"
          end

          # end

          # printer = RubyProf::CallStackPrinter.new(result)
          # File.open("tmp/ruby_prof_callstack_#{Time.zone.now}.html", "w") do |file|
          #   printer.print(file)
          # end
        end

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end

      true
    end
  end
end
