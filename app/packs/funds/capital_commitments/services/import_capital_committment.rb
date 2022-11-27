class ImportCapitalCommittment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Committed Amount", "Notes"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      if save_capital_commitment(user_data, import_upload, custom_field_headers)
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

  def save_capital_commitment(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_commitment #{user_data}" }

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first
    folio_id = user_data["Folio Id"].presence

    if fund && investor

      if CapitalCommitment.exists?(entity_id: import_upload.entity_id, fund:, investor:, folio_id:)
        raise "Committment Already Present"
      else

        # Make the capital_commitment
        capital_commitment = CapitalCommitment.new(entity_id: import_upload.entity_id, folio_id:,
                                                   fund:, investor:, notes: user_data["Notes"])

        capital_commitment.committed_amount = user_data["Committed Amount"].to_d

        setup_custom_fields(user_data, capital_commitment, custom_field_headers)

        capital_commitment.save
      end
    else
      raise fund ? "Investor not found" : "Fund not found"
    end
  end

  def setup_custom_fields(user_data, capital_commitment, custom_field_headers)
    # Were any custom fields passed in ? Set them up
    if custom_field_headers.length.positive?
      capital_commitment.properties ||= {}
      custom_field_headers.each do |cfh|
        capital_commitment.properties[cfh.parameterize.underscore] = user_data[cfh]
      end
    end
  end
end
