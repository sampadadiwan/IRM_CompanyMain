class ImportHolding < ImportUtil
  STANDARD_HEADERS = ["Funding Round or Option Pool", "Employee ID", "Email",
                      "First Name", "Last Name", "Founder or Employee", "Instrument", "Quantity",
                      "Price", "Grant Date (mm/dd/yyyy)"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload)
    # create hash from headers and cells

    user_data = [headers, row].transpose.to_h
    begin
      if save_holding(user_data, import_upload, custom_field_headers)
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

  def save_user(user_data, import_upload, _custom_field_headers)
    # Find the Founder or Employee Investor for the entity
    investor = Investor.where(entity_id: import_upload.owner_id,
                              is_holdings_entity: true, category: user_data["Founder or Employee"]).first

    # Create the user if he does not exists
    user = User.find_by(email: user_data['Email'].strip)
    unless user
      password = (0...8).map { rand(65..90).chr }.join

      user = User.new(email: user_data["Email"], password:,
                      first_name: user_data["First Name"],
                      last_name: user_data["Last Name"], active: true, system_created: true,
                      entity_id: investor.investor_entity_id)

      user.skip_confirmation! if user_data["Send Confirmation Email"] && user_data["Send Confirmation Email"].strip == "No"
      user.save
    end

    # create the Investor Access
    if InvestorAccess.where(email: user_data['Email'], investor_id: investor.id).first.blank?
      InvestorAccess.create(email: user_data["Email"], approved: true, entity_id: import_upload.owner_id,
                            investor_id: investor.id, granted_by: import_upload.user_id)

    end

    [user, investor]
  end

  def save_holding(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing holdings #{user_data}" }

    user, investor = save_user(user_data, import_upload, custom_field_headers)

    fr, ep, grant_date = get_fr_ep(user_data, import_upload)
    price_cents = ep ? ep.excercise_price_cents : user_data["Price"].to_f * 100

    holding = Holding.new(user:, investor:, holding_type: user_data["Founder or Employee"],
                          entity_id: import_upload.owner_id, orig_grant_quantity: user_data["Quantity"],
                          price_cents:, employee_id: user_data["Employee ID"], department: user_data["Department"],
                          investment_instrument: user_data["Instrument"], funding_round: fr, option_pool: ep,
                          import_upload_id: import_upload.id, grant_date:, approved: false,
                          option_type: user_data["Option Type"], preferred_conversion: user_data["Preferred Conversion"])

    setup_custom_fields(user_data, holding, custom_field_headers)

    CreateHolding.call(holding:).holding
  end

  def get_fr_ep(user_data, import_upload)
    if user_data["Instrument"] == "Options"
      ep = option_pool(user_data, import_upload)
      fr = ep.funding_round
    else
      fr = funding_round(user_data, import_upload)
      ep = nil
    end

    date_val = user_data["Grant Date (mm/dd/yyyy)"]
    begin
      grant_date = if date_val.present?
                     Date.strptime(date_val.to_s, "%m/%d/%Y")
                   else
                     Time.zone.today
                   end
    rescue StandardError
      grant_date = DateTime.parse(date_val.to_s)
    end

    [fr, ep, grant_date]
  end

  def funding_round(user_data, import_upload)
    # Create the Holding
    col = "Funding Round or Option Pool"
    fr = FundingRound.where(entity_id: import_upload.owner_id, name: user_data[col].strip).first
    fr ||= FundingRound.create(name: user_data[col].strip,
                               entity_id: import_upload.owner_id,
                               currency: import_upload.owner.currency,
                               status: "Open")

    fr
  end

  def option_pool(user_data, import_upload)
    # Create the Holding
    col = "Funding Round or Option Pool"
    option_pool = OptionPool.approved.where(entity_id: import_upload.owner_id, name: user_data[col].strip).first

    raise "Option Pool #{user_data[col].strip} not available. Please create or approve the pool before uploading" unless option_pool

    option_pool
  end
end
