class ImportInterest < ImportUtil
  STANDARD_HEADERS = ["Buyer Entity Name", "Address", "Contact Name", "Email", "City", "Pan", "Demat", "Bank Account", "Ifsc Code", "Buyer Signatory Emails", "Investor", "Quantity", "Price", "Shortlisted", "Escrow Deposited", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, ctx)
    Rails.logger.debug { "Processing interest #{user_data}" }

    email = user_data["Email"]
    update_only = user_data["Update Only"] == "Yes"
    user = User.find_by(email:)
    short_listed = user_data["Shortlisted"] == "Yes"
    escrow_deposited = user_data["Escrow Deposited"] == "Yes"
    investor = Investor.find_by(entity_id: import_upload.entity_id, investor_name: user_data["Investor"])
    raise "User #{email} not found" unless user

    # Get the Secondary Sale
    secondary_sale = import_upload.owner

    if update_only
      raise "No Interest Id specified for update" unless user_data["Interest Id"]

      interest = Interest.find_by(entity_id: import_upload.entity_id, user_id: user.id, investor_id: investor.id, secondary_sale_id: secondary_sale.id, id: user_data["Interest Id"])
      raise "No interest found for update, for user with #{email}" unless interest
    else
      interest = Interest.new(entity_id: import_upload.entity_id, user_id: user.id, investor_id: investor.id, secondary_sale_id: secondary_sale.id)
    end

    interest.assign_attributes(address: user_data["Address"], PAN: user_data["Pan"], email: user_data["Email"], contact_name: user_data["Contact Name"], bank_account_number: user_data["Bank Account"], ifsc_code: user_data["Ifsc Code"], quantity: user_data["Quantity"], price: user_data["Price"], import_upload_id: import_upload.id, short_listed:, escrow_deposited:, buyer_signatory_emails: user_data["Buyer Signatory Emails"], buyer_entity_name: user_data["Buyer Entity Name"], city: user_data["City"], demat: user_data["Demat"])

    # For SecondarySale we can have multiple form types. We need to set the form type for the interest
    ctx[:form_type_id] = secondary_sale.interest_form_type_id
    interest.form_type_id = secondary_sale.interest_form_type_id

    setup_custom_fields(user_data, interest, custom_field_headers - ["Interest Id", "Update Only"])

    interest.save!
  end
end
