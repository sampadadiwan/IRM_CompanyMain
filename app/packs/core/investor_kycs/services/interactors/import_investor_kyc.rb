class ImportInvestorKyc < ImportUtil
  include Interactor

  STANDARD_HEADERS = ["Investor", "First Name", "Last Name", "email", "PAN", "Address",
                      "Bank Account", "IFSC Code", "Send Confirmation Email"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_investor_kyc(user_data, import_upload, custom_field_headers)
    # puts "processing #{user_data}"
    saved = true

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first
    email = user_data['email'].strip

    investor_kyc = InvestorKyc.where(investor_id: investor.id, entity_id: import_upload.entity_id, email:).first

    if investor_kyc.present?
      Rails.logger.debug { "InvestorKyc with investor already exists for entity #{import_upload.entity_id}" }
    else

      Rails.logger.debug user_data
      investor_kyc = InvestorKyc.new(investor:, PAN: user_data["PAN"]&.strip,
                                     full_name: user_data["Full Name"]&.strip,
                                     first_name: user_data["First Name"]&.strip,
                                     last_name: user_data["Last Name"]&.strip,
                                     email: user_data["email"]&.strip,
                                     address: user_data["Address"]&.strip,
                                     bank_account_number: user_data["Bank Account"],
                                     ifsc_code: user_data["IFSC Code"],
                                     send_confirmation: user_data["Send Confirmation Email"] == "Yes",
                                     entity_id: import_upload.entity_id)

      setup_custom_fields(user_data, investor_kyc, custom_field_headers)

      Rails.logger.debug { "Saving InvestorKyc with email '#{investor_kyc.email}'" }
      saved = investor_kyc.save!

    end

    saved
  end

  def process_row(headers, custom_field_headers, row, import_upload)
    # create hash from headers and cells

    user_data = [headers, row].transpose.to_h
    Rails.logger.debug { "#### user_data = #{user_data}" }
    begin
      if save_investor_kyc(user_data, import_upload, custom_field_headers)
        import_upload.processed_row_count += 1
        row << "Success"
      else
        import_upload.failed_row_count += 1
        row << "Error"
      end
    rescue StandardError => e
      Rails.logger.debug e.message
      row << "Error #{e.message}"
      Rails.logger.debug user_data
      Rails.logger.debug row
      import_upload.failed_row_count += 1
    end
  end
end
