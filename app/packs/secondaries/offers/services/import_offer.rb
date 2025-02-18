class ImportOffer < ImportUtil
  STANDARD_HEADERS = ["Email", "Investor", "Quantity", "Price", "Full Name", "Address", "Pan", "Bank Account", "Ifsc Code", "Seller Signatory Emails", "Approved"].freeze

  IGNORE_CF_HEADERS = ["Id", "User", "Update Only", "Created", "Updated", "Verified", "Pan Verified", "Bank Account Verified", "SPA Accepted"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def ignore_headers
    IGNORE_CF_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, ctx)
    Rails.logger.debug { "Processing offer #{user_data}" }

    email, update_only, approved, offer_type, user, secondary_sale, full_name = get_key_data(user_data, import_upload)

    # This offer is for an investor
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    raise "Investor #{user_data['Investor']} not found" unless investor

    # Make the offer
    if update_only
      raise "No Offer Id specified for update" unless user_data["Id"]

      offer = Offer.find_by(entity_id: import_upload.entity_id, id: user_data["Id"])
      raise "No offer found for update, for user with #{email}, secondary_sale_id #{secondary_sale.id}, #{user_data['Pan']} " if offer.nil?

      unless OfferPolicy.new(import_upload.user, offer).update?
        if offer.verified
          raise "Offer #{offer.id} is verified. Cannot update"
        else
          raise "User #{import_upload.user} cannot update offer #{offer.id}"
        end
      end
    else
      offer = Offer.new(entity_id: import_upload.entity_id, user_id: user.id, investor_id: investor.id, secondary_sale_id: secondary_sale.id)
    end

    offer.assign_attributes(address: user_data["Address"], city: user_data["City"], PAN: user_data["Pan"], demat: user_data["Demat"], quantity: user_data["Quantity"], price: user_data["Price"], bank_account_number: user_data["Bank Account"], ifsc_code: user_data["Ifsc Code"], final_price: secondary_sale.final_price, import_upload_id: import_upload.id, full_name:, offer_type:, seller_signatory_emails: user_data["Seller Signatory Emails"])

    # For SecondarySale we can have multiple form types. We need to set the form type for the offer
    ctx[:form_type_id] = secondary_sale.offer_form_type_id
    offer.form_type_id = secondary_sale.offer_form_type_id

    setup_custom_fields(user_data, offer, custom_field_headers - IGNORE_CF_HEADERS)

    AccessRight.create(owner: offer.secondary_sale, entity: offer.entity, access_to_investor_id: offer.investor_id, metadata: "Seller")
    offer.save!

    # we need to approve the offer based on the data in the file
    approved ? approve_offer(offer, import_upload) : true
  end

  def approve_offer(offer, import_upload)
    # Approve the offer if required
    if OfferPolicy.new(import_upload.user, offer).approve?
      result = OfferApprove.call(offer:, current_user: import_upload.user)
      raise "Error approving offer #{offer.errors.full_messages}" unless result.success?

      result.success?
    else
      Rails.logger.debug { "Skipping approval for offer #{offer.id} for user #{import_upload.user}" }
      true
    end
  end

  def get_key_data(user_data, import_upload)
    email = user_data["Email"]
    update_only = user_data["Update Only"] == "Yes" || user_data["Id"].present?
    approved = user_data["Approved"] == "Yes"
    offer_type = "Investor"
    full_name = user_data['Full Name']
    # Get the user
    user = User.find_by(email:)
    user ||= import_upload.user

    # Get the Secondary Sale
    secondary_sale = import_upload.owner

    [email, update_only, approved, offer_type, user, secondary_sale, full_name]
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
