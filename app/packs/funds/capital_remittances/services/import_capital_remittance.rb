class ImportCapitalRemittance < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Capital Call", "Due Amount", "Collected Amount", "Status", "Verified"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      if save_capital_remittance(user_data, import_upload, custom_field_headers)
        import_upload.processed_row_count += 1
        row << "Success"
      else
        import_upload.failed_row_count += 1
        row << "Error"
      end
    rescue StandardError => e
      Rails.logger.debug e.backtrace
      row << "Error #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  def save_capital_remittance(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_remittance #{user_data}" }

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first
    capital_call = fund.capital_calls.where(name: user_data["Capital Call"].strip).first
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first

    if fund && capital_call && investor
      if CapitalRemittance.exists?(entity_id: import_upload.entity_id, fund:, capital_call:, investor:)
        raise "Capital Remittance Already Present"
      else

        # Make the capital_remittance
        capital_remittance = CapitalRemittance.new(entity_id: import_upload.entity_id, fund:, capital_call:, investor:, status: user_data["Status"])

        capital_remittance.folio_id = user_data["Folio Id"]
        capital_remittance.call_amount = user_data["Due Amount"]
        capital_remittance.collected_amount = user_data["Collected Amount"]
        capital_remittance.verified = user_data["Verified"] == "Yes"

        setup_custom_fields(user_data, capital_remittance, custom_field_headers)

        capital_remittance.save!
      end
    else
      raise "Fund not found" unless fund
      raise "Capital Call not found" unless capital_call
      raise "Investor not found" unless investor
    end
  end
end
