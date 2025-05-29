module AccountEntryAllocation
  ############################################################
  # 11. CumulateForPortfolioCompany Operation
  ############################################################
  class CumulateForPortfolioCompany < AllocationBaseOperation
    step :cumulate_account_entries

    def parent_ids_for_portfolio_company(fund, fund_formula, portfolio_company)
      parent_type, _attribute = fund_formula.formula.split(',').map(&:strip)

      case parent_type
      when "PortfolioInvestment"
        fund.portfolio_investments.where(portfolio_company_id: portfolio_company.id).pluck(:id).uniq
      when "AggregatePortfolioInvestment"
        fund.aggregate_portfolio_investments.where(portfolio_company_id: portfolio_company.id).pluck(:id).uniq
      else
        raise "Unknown formula type: #{parent_type}"
      end
    end

    def cumulate_account_entries(ctx, for_folios:, **)
      fund_formula = ctx[:fund_formula]
      end_date = ctx[:end_date]
      start_date = ctx[:start_date]
      fund         = ctx[:fund]
      bulk_records = []

      portfolio_companies = fund.entity.investors.joins(:portfolio_investments)
                                .where(portfolio_investments: { fund_id: fund.id })
                                .where(portfolio_investments: { investment_date: ..end_date })
                                .distinct

      portfolio_companies.each do |portfolio_company|
        Rails.logger.debug { "Cumulating #{fund_formula} to #{portfolio_company}" }
        new_records = process_portfolio_company(
          portfolio_company, fund, fund_formula, start_date, end_date, for_folios, ctx[:allocation_run_id]
        )
        bulk_records.concat(new_records)
      end

      if bulk_records.present?
        count = AccountEntry.insert_all(bulk_records)
        Rails.logger.debug { "#{fund_formula.name}: Inserted #{count} records" }
      end

      true
    end

    private

    def process_portfolio_company(portfolio_company, fund, fund_formula, start_date, end_date, for_folios, allocation_run_id)
      records_for_company = []
      if for_folios
        fund.capital_commitments.each do |capital_commitment|
          account_entries = capital_commitment.account_entries
          attributes = create_cumulative_ae_attributes(
            account_entries, portfolio_company, fund, fund_formula,
            start_date, end_date, allocation_run_id
          )
          records_for_company << attributes
        end
      else
        account_entries = fund.account_entries
        attributes = create_cumulative_ae_attributes(
          account_entries, portfolio_company, fund, fund_formula,
          start_date, end_date, allocation_run_id
        )
        records_for_company << attributes
      end
      records_for_company
    end

    def create_cumulative_ae_attributes(account_entries, portfolio_company, fund, fund_formula, start_date, end_date, allocation_run_id)
      cumulative_ae = build_cumulative_account_entry(
        portfolio_company, fund, fund_formula, end_date, allocation_run_id
      )

      cumulative_ae.setup_defaults
      parent_ids = parent_ids_for_portfolio_company(fund, fund_formula, portfolio_company)

      parent_type, name_or_entry_type = fund_formula.formula.split(',').map(&:strip)

      account_entries_query = if name_or_entry_type.downcase == "entrytype"
                                account_entries.where(entry_type: fund_formula.name)
                              else
                                # default is name
                                account_entries.where(name: fund_formula.name)
                              end

      amount_cents = account_entries_query.not_cumulative.where(
        reporting_date: start_date..end_date,
        parent_id: parent_ids,
        parent_type: parent_type
      ).sum(:amount_cents)

      cumulative_ae.amount_cents = amount_cents
      cumulative_ae.rule_for = "reporting"

      cumulative_ae.attributes.except("id", "created_at", "updated_at", "generated_deleted")
    end

    def build_cumulative_account_entry(portfolio_company, fund, fund_formula, end_date, allocation_run_id)
      AccountEntry.new(
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
        allocation_run_id: allocation_run_id
      )
    end
  end
end
