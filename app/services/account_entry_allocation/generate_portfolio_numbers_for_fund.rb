module AccountEntryAllocation
  ############################################################
  # 7. GeneratePortfolioNumbersForFund Operation
  # This FundFurmla is used to generate portfolio company values for a fund
  # Ex FMV for the portfolio company in this fund on this date
  ############################################################
  class GeneratePortfolioNumbersForFund < AllocationBaseOperation
    step :allocate_portfolios_company

    def allocate_portfolios_company(ctx, **)
      fund = ctx[:fund]
      commitment_cache = ctx[:commitment_cache]
      fund_formula = ctx[:fund_formula]
      start_date   = ctx[:start_date]
      end_date     = ctx[:end_date]
      sample       = ctx[:sample]
      user_id      = ctx[:user_id]

      Rails.logger.debug { "GeneratePortfolioNumbersForFund(#{fund_formula.name})" }

      portfolio_companies = fund.entity.investors.joins(:portfolio_investments)
                                .where(portfolio_investments: { fund_id: fund.id })
                                .where(portfolio_investments: { investment_date: ..end_date })
                                .distinct

      portfolio_companies.each_with_index do |portfolio_company, idx|
        ae = AccountEntry.new(
          name: fund_formula.name,
          entry_type: fund_formula.entry_type,
          entity_id: fund.entity_id,
          fund: fund,
          parent: portfolio_company,
          reporting_date: end_date,
          period: "As of #{end_date}",
          generated: true,
          fund_formula: fund_formula
        )

        begin
          # Do not remove this line, its used inside the eval. Rubocop will try and remove it, if its not used
          aggregate_portfolio_investment = portfolio_company.aggregate_portfolio_investment(fund_id: fund.id, as_of: end_date)

          Rails.logger.debug { "Aggregate Portfolio Investment: fmv = #{aggregate_portfolio_investment.fmv}, net_amount = #{aggregate_portfolio_investment.net_amount}, amount = #{aggregate_portfolio_investment.amount}" }

          create_instance_variables(ctx)

          AccountEntryAllocation::CreateAccountEntry.call(ctx.merge(account_entry: ae, capital_commitment: nil, parent: portfolio_company, bdg: binding))
        rescue StandardError => e
          raise "Error in #{fund_formula.name} for #{fund}: #{e.message}"
        end

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end

      true
    end
  end
end
