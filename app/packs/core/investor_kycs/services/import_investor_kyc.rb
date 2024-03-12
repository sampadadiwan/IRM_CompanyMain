class ImportInvestorKyc < ImportUtil
  STANDARD_HEADERS = ["Investor", "Investing Entity", "Pan", "Address", "Correspondence Address", "Kyc Type", "Residency", "Date Of Birth", "Bank Name", "Branch Name", "Bank Account Number", "Account Type", "Ifsc Code", "Verified", "Update Only", "Send Kyc Form To User", "Investor Signatory Emails", "Agreement Committed Amount"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers)
    Rails.logger.debug user_data

    saved = true
    full_name = user_data["Investing Entity"]
    update_only = user_data["Update Only"]
    pan = user_data["Pan"]

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    raise "Investor not found" unless investor

    investor_kyc = InvestorKyc.where(investor_id: investor.id, PAN: pan,
                                     entity_id: import_upload.entity_id, full_name:).first

    if investor_kyc.present? && update_only == "Yes"
      investor_kyc.import_upload_id = import_upload.id
      save_kyc(investor_kyc, investor, user_data, custom_field_headers)

    elsif investor_kyc.nil?
      investor_kyc = InvestorKyc.new(entity_id: import_upload.entity_id, import_upload_id: import_upload.id)
      save_kyc(investor_kyc, investor, user_data, custom_field_headers)

    else
      raise "Skipping: InvestorKyc for investor already exists"
    end

    saved
  end

  def save_kyc(investor_kyc, investor, user_data, custom_field_headers)
    kyc_type = user_data["Kyc Type"].presence || "Individual"

    investor_kyc.assign_attributes(investor:, PAN: user_data["Pan"],
                                   agreement_committed_amount: user_data["Agreement Committed Amount"],
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
                                   verified: user_data["Verified"] == "Yes",
                                   send_kyc_form_to_user: user_data["Send Kyc Form To User"] == "Yes")

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
