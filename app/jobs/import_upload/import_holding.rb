class ImportHolding
  include Interactor
  STANDARD_HEADERS = ["Funding Round or Option Pool", "Employee ID", "Email",
                      "First Name", "Last Name", "Founder or Employee", "Instrument", "Quantity",
                      "Price", "Grant Date (mm/dd/yyyy)"].freeze
  def call
    if context.import_upload.present? && context.import_file.present?
      process_holdings(context.import_file, context.import_upload)
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def process_holdings(_file, import_upload)
    headers = context.headers
    custom_field_headers = headers - STANDARD_HEADERS

    data = context.data

    # Parse the XL rows
    package = Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Import Results") do |sheet|
        data.each_with_index do |row, idx|
          # skip header row
          next if idx.zero?

          process_row(headers, custom_field_headers, row, import_upload)
          # add row to results sheet
          sheet.add_row(row)
          # To indicate progress
          import_upload.save if (idx % 10).zero?
        end
      end
    end

    File.write("/tmp/import_result_#{import_upload.id}.xlsx", package.to_stream.read)
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
    rescue StandardError => e
      row << "Error #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  def save_holding(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing holdings #{user_data}" }

    # Find the Founder or Employee Investor for the entity
    investor = Investor.where(entity_id: import_upload.owner_id,
                              is_holdings_entity: true, category: user_data["Founder or Employee"]).first

    # Create the user if he does not exists
    user = User.find_by(email: user_data['Email'])
    unless user
      password = (0...8).map { rand(65..90).chr }.join
      user = User.create!(email: user_data["Email"], password:,
                          first_name: user_data["First Name"],
                          last_name: user_data["Last Name"], active: true, system_created: true,
                          entity_id: investor.investor_entity_id)

    end

    # create the Investor Access
    if InvestorAccess.where(email: user_data['Email'], investor_id: investor.id).first.blank?
      InvestorAccess.create(email: user_data["Email"], approved: true, entity_id: import_upload.owner_id,
                            investor_id: investor.id, granted_by: import_upload.user_id)

    end

    fr, ep, grant_date = get_fr_ep(user_data, import_upload)
    price_cents = ep ? ep.excercise_price_cents : user_data["Price"].to_f * 100

    holding = Holding.new(user:, investor:, holding_type: user_data["Founder or Employee"],
                          entity_id: import_upload.owner_id, orig_grant_quantity: user_data["Quantity"],
                          price_cents:, employee_id: user_data["Employee ID"], department: user_data["Department"],
                          investment_instrument: user_data["Instrument"], funding_round: fr, option_pool: ep,
                          import_upload_id: import_upload.id, grant_date:, approved: false,
                          option_type: user_data["Option Type"])

    setup_custom_fields(user_data, holding, custom_field_headers)

    CreateHolding.call(holding:).holding
  end

  def setup_custom_fields(user_data, holding, custom_field_headers)
    # Were any custom fields passed in ? Set them up
    if custom_field_headers.length.positive?
      holding.properties ||= {}
      custom_field_headers.each do |cfh|
        holding.properties[cfh.underscore] = user_data[cfh]
      end
    end
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
