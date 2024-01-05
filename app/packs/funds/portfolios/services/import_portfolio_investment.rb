class ImportPortfolioInvestment < ImportUtil
  include Interactor

  STANDARD_HEADERS = ["Fund", "Portfolio Company Name",	"Investment Date",	"Amount",
                      "Quantity",	"Category", "Sub Category", "Sector", "Startup", "Investment Domicile", "Notes", "Type", "Folio No"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(import_upload, _context)
    # This ensures all the counters for this funds API are fixed
    PortfolioInvestment.counter_culture_fix_counts only: :aggregate_portfolio_investment, where: { fund_id: import_upload.owner_id }
    # This will cause the compute_avg_cost to be called
    AggregatePortfolioInvestment.where(fund_id: import_upload.owner_id).find_each(&:save)
  end

  def save_portfolio_investment(user_data, import_upload, custom_field_headers)
    portfolio_company_name, investment_date, amount_cents, quantity, category, sub_category, sector, startup, investment_domicile, fund, commitment_type, capital_commitment = inputs(user_data, import_upload)

    portfolio_investment = PortfolioInvestment.find_or_initialize_by(
      portfolio_company_name:, investment_date:, category:, sub_category:, amount_cents:, quantity:, sector:, startup:, capital_commitment:, commitment_type:, investment_domicile:, fund:, entity_id: fund.entity_id
    )

    if portfolio_investment.new_record?

      Rails.logger.debug user_data

      # Setup the portfolio_company if required
      pcs = fund.entity.investors.portfolio_companies
      portfolio_company = pcs.where(investor_name: portfolio_company_name, category: "Portfolio Company").first
      raise "PortfolioCompany #{portfolio_company_name} not found" if portfolio_company.nil?

      # Save the PortfolioInvestment
      setup_custom_fields(user_data, portfolio_investment, custom_field_headers)
      portfolio_investment.notes = user_data["Notes"]
      portfolio_investment.created_by_import = true
      portfolio_investment.portfolio_company = portfolio_company
      Rails.logger.debug { "Saving PortfolioInvestment with name '#{portfolio_investment.portfolio_company_name}'" }
      portfolio_investment.save!
    else
      raise "PortfolioInvestment already exists"
    end
  end

  def inputs(user_data, import_upload)
    portfolio_company_name = user_data['Portfolio Company Name']
    investment_date = user_data["Investment Date"]
    amount_cents = user_data["Amount"].to_d * 100
    quantity = user_data["Quantity"].to_d
    category = user_data["Category"]
    sub_category = user_data["Sub Category"]
    sector = user_data["Sector"]
    startup = user_data["Startup"] == "Yes"
    investment_domicile = user_data["Investment Domicile"]
    fund = import_upload.entity.funds.where(name: user_data["Fund"]).last
    commitment_type = user_data["Type"]
    folio_id = user_data["Folio No"].presence
    capital_commitment = commitment_type == "CoInvest" ? fund.capital_commitments.where(folio_id:).first : nil

    [portfolio_company_name, investment_date, amount_cents, quantity, category, sub_category, sector, startup, investment_domicile, fund, commitment_type, capital_commitment]
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
    # create hash from headers and cells

    user_data = [headers, row].transpose.to_h
    Rails.logger.debug { "#### user_data = #{user_data}" }
    begin
      if save_portfolio_investment(user_data, import_upload, custom_field_headers)
        import_upload.processed_row_count += 1
        row << "Success"
      else
        import_upload.failed_row_count += 1
        row << "Error"
      end
    rescue ActiveRecord::Deadlocked => e
      raise e
    rescue StandardError => e
      Rails.logger.debug e.message
      row << "Error #{e.message}"
      Rails.logger.debug user_data
      Rails.logger.debug row
      import_upload.failed_row_count += 1
    end
  end
end
