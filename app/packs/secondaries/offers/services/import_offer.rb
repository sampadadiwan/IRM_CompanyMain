class ImportOffer < ImportUtil
  STANDARD_HEADERS = ["Email", "Offer Quantity", "First Name", "Last Name", "Address", "Pan", "Bank Account", "Ifsc Code", "Founder/Employee/Investor", "Investor", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing offer #{user_data}" }

    email = user_data["Email"]
    update_only = user_data["Update Only"] == "Yes"
    user = User.find_by(email:)
    raise "User #{email} not found" unless user

    if user_data["Founder/Employee/Investor"] == "Investor"
      # This offer is for an investor
      investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
      raise "Investor #{user_data['Investor']} not found" unless investor

      # Get the holding for which the offer is being made
      holding = Holding.where("holdings.investor_id=? and holdings.entity_id=?", investor.id, import_upload.entity_id).last

      raise "User not found for investor #{user_data['Investor']}" unless user.entity_id == investor.investor_entity_id

    else

      # Get the holding for which the offer is being made
      holding = Holding.joins(:user).where("users.email=? and holdings.entity_id=?", email, import_upload.entity_id).last

    end
    # Get the Secondary Sale
    secondary_sale = import_upload.owner
    # Make the offer

    full_name = "#{user_data['First Name']} #{user_data['Last Name']}"

    if holding

      offer = Offer.find_or_initialize_by(entity_id: import_upload.entity_id, user_id: user.id, investor_id: holding.investor_id, secondary_sale_id: secondary_sale.id, PAN: user_data["Pan"])

      if update_only
        raise "No offer found for update, for user with #{email}, secondary_sale_id #{secondary_sale.id}, #{user_data['Pan']} " if offer.new_record?
      else
        offer.holding_id = holding.id
      end

      offer.assign_attributes(address: user_data["Address"], city: user_data["City"],
                              demat: user_data["Demat"], quantity: user_data["Offer Quantity"], bank_account_number: user_data["Bank Account"], ifsc_code: user_data["Ifsc Code"], final_price: secondary_sale.final_price, import_upload_id: import_upload.id, full_name:)

      setup_custom_fields(user_data, offer, custom_field_headers)

      offer.save!
    else
      raise "No holding found for user with email #{email}"
    end
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
