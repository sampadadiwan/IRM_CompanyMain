class ImportPortfolioCashflow < ImportUtil
  STANDARD_HEADERS = ["Fund", "Portfolio Company",	"Payment Date",	"Amount", "Tag", "Instrument",
                      "Instrument", "Notes"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    fund_id, portfolio_company, payment_date, amount_cents, tag, instrument_name = inputs(user_data, import_upload)

    # A blank Instrument used to look up name: nil and report "not found", which
    # pointed at the wrong problem - the value is missing, not wrong
    raise "Instrument must be specified" if instrument_name.blank?

    investment_instrument = portfolio_company.investment_instruments.where(name: instrument_name).first
    raise "Investment Instrument '#{instrument_name}' not found for #{portfolio_company.investor_name}" if investment_instrument.nil?

    aggregate_pi = import_upload.entity.aggregate_portfolio_investments.where(fund_id:, portfolio_company_id: portfolio_company.id, investment_instrument:).first
    raise "No investment in #{portfolio_company.investor_name} (#{instrument_name}) found for this fund - add the portfolio investment first" if aggregate_pi.nil?

    portfolio_cashflow = PortfolioCashflow.find_or_initialize_by(entity_id: import_upload.entity_id, fund_id:,
                                                                 portfolio_company_id: portfolio_company.id,
                                                                 tag:, investment_instrument:,
                                                                 aggregate_portfolio_investment_id: aggregate_pi.id, payment_date:, amount_cents:)

    if portfolio_cashflow.new_record?

      Rails.logger.debug user_data

      # Save the PortfolioCashflow
      setup_custom_fields(user_data, portfolio_cashflow, custom_field_headers)
      portfolio_cashflow.notes = user_data["Notes"]
      portfolio_cashflow.import_upload_id = import_upload.id
      Rails.logger.debug { "Saving PortfolioCashflow with name '#{portfolio_cashflow.portfolio_company.investor_name}'" }
      portfolio_cashflow.save!
    else
      raise "A #{tag} cashflow of #{amount_cents / 100} for #{portfolio_company.investor_name} (#{instrument_name}) on #{payment_date} already exists"
    end
  end

  def inputs(user_data, import_upload)
    portfolio_company_name = user_data['Portfolio Company']
    portfolio_company = import_upload.entity.investors.where(investor_name: portfolio_company_name).first
    raise "Portfolio Company not found: #{portfolio_company_name}" if portfolio_company.nil?

    payment_date = user_data["Payment Date"]
    amount_cents = user_data["Amount"].to_d * 100
    tag = user_data["Tag"].presence || "Actual"
    instrument_name = user_data["Instrument"].presence || nil

    fund = import_upload.entity.funds.where(name: user_data["Fund"]).last
    raise "Fund not found: #{user_data['Fund']}" if fund.nil?

    fund_id = fund.id

    [fund_id, portfolio_company, payment_date, amount_cents, tag, instrument_name]
  end
end
