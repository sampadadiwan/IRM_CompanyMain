class ImportOffer < ImportUtil
  STANDARD_HEADERS = ["Email", "Offer Quantity", "First Name", "Middle Name", "Last Name", "Address", "PAN", "Bank Account", "IFSC Code"].freeze

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

    email = user_data["Email"].strip
    # Get the holding for which the offer is being made
    holding = Holding.joins(:user).where("users.email=? and holdings.entity_id=?",
                                         email, import_upload.entity_id).first
    # Get the Secondary Sale
    secondary_sale = import_upload.owner
    # Make the offer

    if holding
      offer = Offer.new(PAN: user_data["PAN"], address: user_data["Address"], city: user_data["City"],
                        demat: user_data["Demat"], quantity: user_data["Offer Quantity"], bank_account_number: user_data["Bank Account"], ifsc_code: user_data["IFSC Code"],
                        holding:, secondary_sale:, final_price: secondary_sale.final_price,
                        user: holding.user, investor: holding.investor, entity: holding.entity,
                        full_name: holding.user&.full_name)

      setup_custom_fields(user_data, offer, custom_field_headers)

      ret_val = offer.save
      raise offer.errors.full_messages.to_s unless ret_val

      ret_val
    else
      raise "No holding found for user with email #{email}"
    end
  end

  def post_process(import_upload, _context)
    # Sometimes we import custom fields. Ensure custom fields get created
    @last_saved = import_upload.entity.offers.last
    FormType.extract_from_db(@last_saved) if @last_saved
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
                                    'users.first_name': first_name.strip,
                                    'users.last_name': last_name.strip).first

      if u
        secondary_sale.offers.where(user_id: u.id).update(
          bank_name: user_data["Bank Name"].strip,
          bank_account_number: user_data["Bank Account Number"].strip,
          ifsc_code: user_data["IFSC CODE"].strip
        )

      else
        Rails.logger.debug { "No user found for row #{idx} #{user_data} #{first_name} #{last_name}" }
      end
    end
  end
end
