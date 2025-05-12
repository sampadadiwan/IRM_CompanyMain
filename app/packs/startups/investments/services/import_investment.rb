class ImportInvestment < ImportUtil
  STANDARD_HEADERS = [
    "Portfolio Company",
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

  IGNORE_CF_HEADERS = ["Id"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def ignore_headers
    IGNORE_CF_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    portfolio_company_name, category, currency, investor_name, investment_type, funding_round, quantity, price, investment_date, notes = inputs(user_data)

    portfolio_company = find_portfolio_company(import_upload, portfolio_company_name)
    entity_id = import_upload.entity_id

    update_only = user_data["Update Only"] == "Yes"

    investment_attrs = {
      portfolio_company: portfolio_company,
      category: category,
      currency: currency,
      investor_name: investor_name,
      investment_type: investment_type,
      funding_round: funding_round,
      investment_date: investment_date,
      quantity: quantity,
      price: price,
      notes: notes
    }

    if update_only
      update_investment(user_data, import_upload, investment_attrs, custom_field_headers)
    else
      create_investment(user_data, import_upload, entity_id, investment_attrs, custom_field_headers)
    end
  end

  private

  def find_portfolio_company(import_upload, portfolio_company_name)
    portfolio_company = import_upload.entity.investors.portfolio_companies.find_by(investor_name: portfolio_company_name)
    raise "Portfolio Company not found" if portfolio_company.nil?

    portfolio_company
  end

  def update_investment(user_data, import_upload, attrs, custom_field_headers)
    raise "No Investment Id specified for update" unless user_data["Id"]

    investment = Investment.find_by(entity_id: import_upload.entity_id, id: user_data["Id"])
    raise "No Investment found for update with ID #{user_data['Id']}" if investment.nil?

    Rails.logger.debug { "Updating Investment with ID '#{investment.id}'" }
    investment.assign_attributes(
      portfolio_company_id: attrs[:portfolio_company].id,
      category: attrs[:category],
      currency: attrs[:currency],
      investor_name: attrs[:investor_name],
      investment_type: attrs[:investment_type],
      funding_round: attrs[:funding_round],
      investment_date: attrs[:investment_date],
      quantity: attrs[:quantity],
      price: attrs[:price],
      notes: attrs[:notes],
      import_upload_id: import_upload.id
    )

    setup_custom_fields(user_data, investment, custom_field_headers - IGNORE_CF_HEADERS)
    investment.save!
  end

  def create_investment(user_data, import_upload, entity_id, attrs, custom_field_headers)
    investment = Investment.new(
      portfolio_company_id: attrs[:portfolio_company].id,
      entity_id: entity_id,
      category: attrs[:category],
      currency: attrs[:currency],
      investor_name: attrs[:investor_name],
      investment_type: attrs[:investment_type],
      funding_round: attrs[:funding_round],
      investment_date: attrs[:investment_date]
    )

    setup_custom_fields(user_data, investment, custom_field_headers)
    investment.quantity = attrs[:quantity]
    investment.price = attrs[:price]
    investment.notes = attrs[:notes]
    investment.import_upload_id = import_upload.id
    investment.portfolio_company = attrs[:portfolio_company]
    Rails.logger.debug { "Saving Investment with ID '#{investment.id}'" }

    investment.save!
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
