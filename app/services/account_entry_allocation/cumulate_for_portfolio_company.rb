module AccountEntryAllocation
  ############################################################
  # 11. CumulateForPortfolioCompany Operation
  ############################################################
  class CumulateForPortfolioCompany < AllocationBaseOperation
    step :cumulate_account_entries

    def parent_ids_for_portfolio_company(fund, fund_formula, portfolio_company)
      case fund_formula.formula.strip
      when "PortfolioInvestment"
        fund.portfolio_investments.where(portfolio_company_id: portfolio_company.id).pluck(:id).uniq
      when "AggregatePortfolioInvestment"
        fund.aggregate_portfolio_investments.where(portfolio_company_id: portfolio_company.id).pluck(:id).uniq
      else
        raise "Unknown formula type: #{fund_formula.formula}"
      end
    end

    def cumulate_account_entries(ctx, **)
      fund_formula = ctx[:fund_formula]
      ctx[:commitment_cache]
      end_date = ctx[:end_date]
      ctx[:sample]
      ctx[:start_date]
      fund         = ctx[:fund]
      bulk_records = []

      portfolio_companies = fund.entity.investors.joins(:portfolio_investments)
                                .where(portfolio_investments: { fund_id: fund.id })
                                .where(portfolio_investments: { investment_date: ..end_date })
                                .distinct

      portfolio_companies.each do |portfolio_company|
        Rails.logger.debug { "Cumulating #{fund_formula} to #{portfolio_company}" }

        cumulative_ae = AccountEntry.new(
          fund_id: fund.id,
          entity_id: fund.entity_id,
          parent: portfolio_company,
          parent_name: portfolio_company.name,
          fund_formula: fund_formula,
          name: fund_formula.name,
          entry_type: fund_formula.entry_type,
          reporting_date: end_date,
          cumulative: true,
          generated: true,
          allocation_run_id: ctx[:allocation_run_id]
        )

        cumulative_ae.setup_defaults
        parent_ids = parent_ids_for_portfolio_company(fund, fund_formula, portfolio_company)

        amount_cents = fund.account_entries.not_cumulative.where(
          name: fund_formula.name,
          reporting_date: ..end_date,
          parent_id: parent_ids,
          parent_type: fund_formula.formula.strip
        ).sum(:amount_cents)

        cumulative_ae.amount_cents = amount_cents

        cumulative_ae.rule_for = "reporting"

        bulk_records << cumulative_ae.attributes.except("id", "created_at", "updated_at", "generated_deleted")
      end

      if bulk_records.present?
        count = AccountEntry.insert_all(bulk_records)
        Rails.logger.debug { "#{fund_formula.name}: Inserted #{count} records" }
      end

      true
    end
  end
end
