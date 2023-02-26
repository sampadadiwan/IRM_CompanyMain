class ImportPortfolioInvestment < ImportUtil
  include Interactor

  STANDARD_HEADERS = ["Fund", "Portfolio Company Name",	"Investment Date",	"Amount",
                      "Quantity",	"Investment Type",	"Notes"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(import_upload, _context); end

  def save_portfolio_investment(user_data, _import_upload, custom_field_headers)
    portfolio_company_name = user_data['Portfolio Company Name'].strip
    investment_date = user_data["Investment Date"]
    amount_cents = user_data["Amount"].to_d * 100
    quantity = user_data["Quantity"].to_d
    investment_type = user_data["Investment Type"].strip
    fund = Fund.find_by_name user_data["Fund"].strip

    portfolio_investment = PortfolioInvestment.find_or_initialize_by(portfolio_company_name:, investment_date:,
                                                                     amount_cents:, quantity:, investment_type:,
                                                                     fund:, entity_id: fund.entity_id)

    if portfolio_investment.new_record?

      Rails.logger.debug user_data
      # Setup the portfolio_company if required
      portfolio_company = fund.entity.investors.portfolio_companies.where(investor_name: portfolio_company_name).first
      if portfolio_company.nil?
        # Create the portfolio_company
        portfolio_company = fund.entity.investors.create!(investor_name: portfolio_company_name, category: "Portfolio Company")
      end
      # Save the PortfolioInvestment
      setup_custom_fields(user_data, portfolio_investment, custom_field_headers)
      portfolio_investment.notes = user_data["Notes"]
      portfolio_investment.portfolio_company = portfolio_company
      Rails.logger.debug { "Saving PortfolioInvestment with name '#{portfolio_investment.portfolio_company_name}'" }
      portfolio_investment.save!
    else
      raise "PortfolioInvestment already exists"
    end
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
