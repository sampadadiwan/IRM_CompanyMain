class ImportOffer < ImportUtil
  STANDARD_HEADERS = ["Email", "Offer Quantity", "First Name", "Last Name", "Address", "PAN", "Bank Account", "Ifsc Code", "Founder/Employee/Investor", "Investor"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      if save_offer(user_data, import_upload, custom_field_headers)
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
      Rails.logger.debug e.backtrace
      row << "Error #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  def save_offer(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing offer #{user_data}" }

    email = user_data["Email"]

    user = User.find_by(email:)
    raise "User #{email} not found" unless user

    if user_data["Founder/Employee/Investor"] == "Investor"
      # This offer is for an investor
      investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
      raise "Investor #{user_data['Investor']} not found" unless investor

      # Get the holding for which the offer is being made
      holding = Holding.where("holdings.investor_id=? and holdings.entity_id=?", investor.id, import_upload.entity_id).first

      raise "User not found for investor #{user_data['Investor']}" unless user.entity_id == investor.investor_entity_id

    else

      # Get the holding for which the offer is being made
      holding = Holding.joins(:user).where("users.email=? and holdings.entity_id=?",
                                           email, import_upload.entity_id).first

    end
    # Get the Secondary Sale
    secondary_sale = import_upload.owner
    # Make the offer

    full_name = "#{user_data['First Name']} #{user_data['Last Name']}"

    if holding
      offer = Offer.new(PAN: user_data["Pan"], address: user_data["Address"], city: user_data["City"],
                        demat: user_data["Demat"], quantity: user_data["Offer Quantity"], bank_account_number: user_data["Bank Account"], ifsc_code: user_data["Ifsc Code"],
                        holding:, secondary_sale:, final_price: secondary_sale.final_price,
                        user:, investor: holding.investor, entity: holding.entity, full_name:)

      setup_custom_fields(user_data, offer, custom_field_headers)

      ret_val = offer.save
      raise offer.errors.full_messages.to_s unless ret_val

      ret_val
    else
      raise "No holding found for user with email #{email}"
    end
  end

  def post_process(import_upload, context)
    # Sometimes we import custom fields. Ensure custom fields get created
    custom_field_headers = context.headers - standard_headers
    FormType.save_cf_from_import(custom_field_headers, import_upload) if import_upload.processed_row_count.positive?
  end

  def adhoc_update(file_path, secondary_sale_id)
    secondary_sale = SecondarySale.find(secondary_sale_id)

    data = Roo::Spreadsheet.open(file_path) # open spreadsheet
    headers = data.row(1) # get header row

    data.each_with_index do |row, idx|
      # skip header row
      next if idx.zero?

      user_data = [headers, row].transpose.to_h

      first_name, last_name = user_data["Seller name"].split
      u = User.joins(:offers).where('offers.entity_id': secondary_sale.entity_id,
                                    'users.first_name': first_name,
                                    'users.last_name': last_name).first

      if u
        secondary_sale.offers.where(user_id: u.id).update(
          bank_name: user_data["Bank Name"],
          bank_account_number: user_data["Bank Account Number"],
          ifsc_code: user_data["Ifsc Code"]
        )

      else
        Rails.logger.debug { "No user found for row #{idx} #{user_data} #{first_name} #{last_name}" }
      end
    end
  end
end
