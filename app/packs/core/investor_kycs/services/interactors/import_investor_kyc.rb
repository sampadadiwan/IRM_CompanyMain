class ImportInvestorKyc < ImportUtil
  include Interactor

  STANDARD_HEADERS = ["Investor", "Full Name", "PAN", "Address",
                      "Bank Account", "IFSC Code", "Send Confirmation Email", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_investor_kyc(user_data, import_upload, custom_field_headers)
    Rails.logger.debug user_data

    saved = true
    full_name = user_data["Full Name"]&.strip
    update_only = user_data["Update Only"]&.strip
    pan = user_data["PAN"]&.strip

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first
    raise "Investor not found" unless investor

    investor_kyc = InvestorKyc.where(investor_id: investor.id, PAN: pan,
                                     entity_id: import_upload.entity_id, full_name:).first

    if investor_kyc.present? && update_only == "Yes"
      save_kyc(investor_kyc, investor, user_data, custom_field_headers)

    elsif investor_kyc.nil? || (investor_kyc.created_at.to_date != Time.zone.today)
      investor_kyc = InvestorKyc.new(entity_id: import_upload.entity_id)
      save_kyc(investor_kyc, investor, user_data, custom_field_headers)

    else
      raise "Skipping: InvestorKyc for investor already exists"
    end

    saved
  end

  def save_kyc(investor_kyc, investor, user_data, custom_field_headers)
    investor_kyc.assign_attributes(investor:, PAN: user_data["PAN"]&.strip,
                                   full_name: user_data["Full Name"]&.strip,
                                   address: user_data["Address"]&.strip,
                                   bank_account_number: user_data["Bank Account"]&.to_s&.strip,
                                   ifsc_code: user_data["IFSC Code"]&.strip,
                                   verified: user_data["Verified"]&.strip == "Yes")

    setup_custom_fields(user_data, investor_kyc, custom_field_headers)

    investor_kyc.save!
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
    rescue ActiveRecord::Deadlocked => e
      raise e
    rescue StandardError => e
      Rails.logger.debug e.message
      row << "Error #{e.message}"
      Rails.logger.debug user_data
      Rails.logger.debug row
      import_upload.failed_row_count += 1
    end
  end
end
