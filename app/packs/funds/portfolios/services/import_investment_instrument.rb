class ImportInvestmentInstrument < ImportUtil
  STANDARD_HEADERS = ["Portfolio Company", "Name", "Currency", "Investment Domicile", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(row_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug row_data

    saved = true
    name = row_data["Name"]&.strip
    raise "Name is required" if name.blank?

    currency = row_data["Currency"]&.to_s&.strip&.upcase
    raise "Currency is required" if currency.blank?

    update_only = row_data["Update Only"]

    portfolio_company = import_upload.entity.investors.where(investor_name: row_data["Portfolio Company"]).first
    raise "Portfolio Company not found" unless portfolio_company

    investment_instrument = InvestmentInstrument.where(portfolio_company_id: portfolio_company.id,
                                                       entity_id: import_upload.entity_id, name:).first

    if update_only == "Yes"
      if investment_instrument.present?
        # Update only, and we have a pre-existing investment_instrument
        raise "Currency cannot be updated" if investment_instrument.currency.to_s.downcase != currency.to_s.downcase

        saved = save_instrument(investment_instrument, portfolio_company, row_data, custom_field_headers, import_upload)
      else
        # Update only, but we dont have a pre-existing investment_instrument
        raise "Skipping: InvestmentInstrument not found for update"
      end
    elsif investment_instrument.nil?
      investment_instrument = InvestmentInstrument.new(entity_id: import_upload.entity_id, import_upload_id: import_upload.id)
      saved = save_instrument(investment_instrument, portfolio_company, row_data, custom_field_headers, import_upload)
    # No update, and we dont have a pre-existing investment_instrument
    else
      # No update, but we have a pre-existing investment_instrument
      raise "Skipping: Investment Instrument for Portfolio Company already exists"
    end

    saved
  end

  def save_instrument(investment_instrument, portfolio_company, row_data, custom_field_headers, import_upload)
    investment_instrument.assign_attributes(portfolio_company:, import_upload_id: import_upload.id,
                                            name: row_data["Name"]&.strip,
                                            currency: row_data["Currency"]&.to_s&.strip&.upcase,
                                            investment_domicile: row_data["Investment Domicile"]&.to_s)

    setup_custom_fields(row_data, investment_instrument, custom_field_headers)

    investment_instrument.save!
  end
end
