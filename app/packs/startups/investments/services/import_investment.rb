class ImportInvestment < ImportUtil
  STANDARD_HEADERS = [
    "Portfolio Company Name",
    "Category",
    "Currency",
    "Investor Name",
    "Investment Type",
    "Funding Round",
    "Quantity",
    "Price",
    "Investment Date",
    "Notes"
  ].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    portfolio_company_name, category, currency, investor_name, investment_type, funding_round, quantity, price, investment_date, notes = inputs(user_data)

    portfolio_company = import_upload.entity.investors.portfolio_companies.find_by(investor_name: portfolio_company_name)
    entity_id = import_upload.entity_id

    raise "Portfolio Company not found" if portfolio_company.nil?

    investment = Investment.find_or_initialize_by(
      portfolio_company_id: portfolio_company.id,
      entity_id: entity_id,
      category: category,
      currency: currency,
      investor_name: investor_name,
      investment_type: investment_type,
      funding_round: funding_round,
      investment_date: investment_date
    )

    if investment.new_record?
      Rails.logger.debug user_data

      # Save the Investment
      setup_custom_fields(user_data, investment, custom_field_headers)
      investment.quantity = quantity
      investment.price = price
      investment.notes = notes
      investment.import_upload_id = import_upload.id
      investment.portfolio_company = portfolio_company
      Rails.logger.debug { "Saving Investment with ID '#{investment.id}'" }

      investment.save!
    else
      raise "Investment already exists"
    end
  end

  def create_custom_fields(ctx, import_upload:, custom_field_headers:, **)
    # Remove any headers that are not related to Investment model's custom fields
    custom_field_headers -= ["Some Irrelevant Field1", "Some Irrelevant Field2"]
    super(ctx, import_upload: import_upload, custom_field_headers: custom_field_headers)
  end

  def inputs(user_data)
    portfolio_company_name = user_data['Portfolio Company']
    category = user_data['Category']
    currency = user_data['Currency']
    investor_name = user_data['Investor Name']
    investment_type = user_data['Investment Type']
    funding_round = user_data['Funding Round']
    quantity = user_data['Quantity'].to_d
    price = user_data['Price'].to_d
    investment_date = user_data['Investment Date']
    notes = user_data['Notes'].presence

    [portfolio_company_name, category, currency, investor_name, investment_type, funding_round, quantity, price, investment_date, notes]
  end

  def defer_counter_culture_updates
    false
  end
end
