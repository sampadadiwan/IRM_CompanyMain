class ImportInterest < ImportUtil
  STANDARD_HEADERS = ["Buyer Entity Name", "Investor", "Address", "Contact Name", "City", "Pan", "Demat", "Bank Account", "Ifsc Code", "Buyer Signatory Emails", "Quantity", "Price", "Short Listed Status", "Escrow Deposited"].freeze

  # These are additional cols in the XL download that are not part of the import
  # Sometimes users download the data, make changes and upload - then these fields should not get saved as CFs.
  IGNORE_CF_HEADERS = ["Id", "Update Only", "Allocation Quantity", "Allocation Amount", "Verified", "Email", "User", "Created", "Updated"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def ignore_headers
    IGNORE_CF_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, ctx)
    Rails.logger.debug { "Processing interest #{user_data}" }

    update_only, user, escrow_deposited, investor = key_data(user_data, import_upload)
    # Get the Secondary Sale
    secondary_sale = import_upload.owner

    if update_only
      raise "No Interest Id specified for update" unless user_data["Id"]

      interest = Interest.find_by(entity_id: import_upload.entity_id, investor_id: investor.id, secondary_sale_id: secondary_sale.id, id: user_data["Id"])
      raise "No interest found for update, for investor with #{investor}" unless interest
    else
      interest = Interest.new(entity_id: import_upload.entity_id, user_id: user.id, investor_id: investor.id, secondary_sale_id: secondary_sale.id)
    end

    interest.assign_attributes(address: user_data["Address"], PAN: user_data["Pan"], contact_name: user_data["Contact Name"], bank_account_number: user_data["Bank Account"], ifsc_code: user_data["Ifsc Code"], import_upload_id: import_upload.id, escrow_deposited:, buyer_signatory_emails: user_data["Buyer Signatory Emails"], city: user_data["City"], demat: user_data["Demat"], user_id: import_upload.user_id)

    # If the interest is not short listed, we can set the quantity and price
    if interest.short_listed_status != Interest::STATUS_SHORT_LISTED
      interest.quantity = user_data["Quantity"]
      interest.price = user_data["Price"]
      interest.buyer_entity_name = user_data["Buyer Entity Name"]
    end

    # Allow only people who can short list to short list
    policy = InterestPolicy.new(import_upload.user, interest)
    if policy.short_list?
      short_listed_status = user_data["Short Listed Status"].downcase.squeeze(" ")
      if policy.owner? 
        # Owners can set the short listed status to anything
        short_listed_status = Interest::STATUS_SHORT_LISTED if ["shortlisted", "short listed"].include?(short_listed_status)
        short_listed_status = Interest::STATUS_PENDING unless Interest::STATUSES.include?(short_listed_status)
        # Assign the short listed status only if the user has the right to do so
        interest.short_listed_status = short_listed_status
      elsif !interest.short_listed && short_listed_status == Interest::STATUS_WITHDRAWN       
        # If the interest is not short listed, we can set the short listed status to withdrawn
        interest.short_listed_status = short_listed_status 
      else
        puts "User #{import_upload.user.email} does not have the right to #{short_listed_status} interest"
      end
    end

    setup_custom_fields(user_data, interest, custom_field_headers - IGNORE_CF_HEADERS)

    # For SecondarySale we can have multiple form types. We need to set the form type for the interest
    ctx[:form_type_id] = secondary_sale.interest_form_type_id
    interest.form_type_id = secondary_sale.interest_form_type_id

    AccessRight.create(owner: interest.secondary_sale, entity: interest.entity, access_to_investor_id: interest.investor_id, metadata: "Buyer")
    interest.save!
  end

  # extract the key data from the user data
  def key_data(user_data, import_upload)
    email = user_data["Email"]
    update_only = user_data["Update Only"] == "Yes" || user_data["Id"].present?
    user = User.where(email:).first
    # If the user is not found, we need to set it up as the user who uploaded the file
    user ||= import_upload.user

    escrow_deposited = user_data["Escrow Deposited"] == "Yes"
    investor = Investor.find_by(entity_id: import_upload.entity_id, investor_name: user_data["Investor"])
    raise "No investor found for #{user_data['Investor']}" unless investor

    [update_only, user, escrow_deposited, investor]
  end
end
