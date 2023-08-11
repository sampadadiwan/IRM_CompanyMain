class ImportCapitalRemittance < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Capital Call", "Call Amount (Inclusive of Capital Fees)", "Capital Fees", "Other Fees", "Status", "Verified", "Folio No"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
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
    rescue ActiveRecord::Deadlocked => e
      raise e
    rescue StandardError => e
      Rails.logger.debug e.backtrace
      row << "Error #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  def save_capital_remittance(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_remittance #{user_data}" }

    fund, capital_call, investor, folio_id, capital_commitment = inputs(import_upload, user_data)

    if fund && capital_call && investor && capital_commitment

      # Make the capital_remittance
      capital_remittance = CapitalRemittance.new(entity_id: import_upload.entity_id, fund:, capital_call:, investor:, investor_name: investor.investor_name, capital_commitment:, status: user_data["Status"], folio_id:, folio_call_amount: user_data["Call Amount (Inclusive of Capital Fees)"], folio_capital_fee: user_data["Capital Fees"], folio_other_fee: user_data["Other Fees"], payment_date: user_data["Payment Date"], created_by: "Upload")

      capital_remittance.verified = user_data["Verified"] == "Yes"

      setup_custom_fields(user_data, capital_remittance, custom_field_headers)
      capital_remittance.set_call_amount
      capital_remittance.save!

    else
      raise "Fund not found" unless fund
      raise "Capital Call not found" unless capital_call
      raise "Investor not found" unless investor
      raise "Capital Commitment not found" unless capital_commitment
    end
  end

  def inputs(import_upload, user_data)
    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first
    capital_call = fund.capital_calls.where(name: user_data["Capital Call"].strip).first
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first
    raise "Investor not found" unless investor

    folio_id = user_data["Folio No"]&.to_s&.strip
    capital_commitment = fund.capital_commitments.where(investor_id: investor.id, folio_id:).first

    [fund, capital_call, investor, folio_id, capital_commitment, collected_amount_cents]
  end
end
