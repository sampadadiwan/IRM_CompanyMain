class ImportInvestorKyc < ImportUtil
  STANDARD_HEADERS = ["Investor", "Investing Entity", "Pan", "Address", "Correspondence Address", "Kyc Type", "Residency", "Date Of Birth", "Bank Name", "Branch Name", "Bank Account Number", "Account Type", "Ifsc Code", "Verified", "Update Only", "Send Kyc Form To User", "Investor Signatory Emails", "Agreement Committed Amount", "Agreement Unit Type"].freeze
  # add them as standard fields above

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug user_data

    saved = true
    full_name = user_data["Investing Entity"]
    update_only = user_data["Update Only"]
    pan = user_data["Pan"]

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    raise "Investor not found" unless investor

    investor_kyc = InvestorKyc.where(investor_id: investor.id, PAN: pan,
                                     entity_id: import_upload.entity_id, full_name:).first

    # Update Only
    # 1. Kyc found - update
    # 2. Kyc not found but there is a kyc with a blank full name or nil full name in the DB - update
    if update_only == "Yes"
      # If kyc is not there, then we need to find one with no full_name and no PAN
      investor_kyc ||= InvestorKyc.where(investor_id: investor.id, PAN: [pan, nil, ""],
                                         entity_id: import_upload.entity_id, full_name: [full_name, nil, ""]).first

      if investor_kyc.present?
        # Update only, and we have a pre-existing KYC
        investor_kyc.import_upload_id = import_upload.id
        saved = save_kyc(investor_kyc, investor, user_data, custom_field_headers)
      else
        # Kyc not found but there is a kyc with a blank full name or nil full name in the DB - update
        # Update only, but we dont have a pre-existing KYC
        raise "Skipping: InvestorKyc not found for update"
      end
    elsif investor_kyc.nil?
      investor_kyc = InvestorKyc.new(entity_id: import_upload.entity_id, import_upload_id: import_upload.id)
      saved = save_kyc(investor_kyc, investor, user_data, custom_field_headers)
      # No update, and we dont have a pre-existing KYC
    else
      # No update, but we have a pre-existing KYC
      raise "Skipping: InvestorKyc for investor already exists"
    end

    saved
  end

  def save_kyc(investor_kyc, investor, user_data, custom_field_headers)
    kyc_type = user_data["Kyc Type"].presence || "Individual"

    verified = %w[yes true].include?(user_data["Verified"]&.downcase)
    send_kyc_form_to_user = %w[yes true].include?(user_data["Send Kyc Form To User"]&.downcase)

    investor_kyc.assign_attributes(investor:, PAN: user_data["Pan"],
                                   agreement_committed_amount: user_data["Agreement Committed Amount"],
                                   agreement_unit_type: user_data["Agreement Unit Type"],
                                   full_name: user_data["Investing Entity"],
                                   address: user_data["Address"],
                                   corr_address: user_data["Correspondence Address"],
                                   birth_date: user_data["Date Of Birth"],
                                   kyc_type:,
                                   esign_emails: user_data["Investor Signatory Emails"],
                                   residency: user_data["Residency"],
                                   bank_name: user_data["Bank Name"],
                                   bank_branch: user_data["Branch Name"],
                                   bank_account_number: user_data["Bank Account Number"]&.to_s,
                                   bank_account_type: user_data["Account Type"],
                                   ifsc_code: user_data["Ifsc Code"],
                                   verified:,
                                   send_kyc_form_to_user:)

    setup_custom_fields(user_data, investor_kyc, custom_field_headers)
    result = if investor_kyc.new_record?
               InvestorKycCreate.call(investor_kyc:, investor_user: false)
             else
               InvestorKycUpdate.call(investor_kyc:, investor_user: false)
             end

    raise result[:errors] unless result.success?

    result.success?
  end
end
