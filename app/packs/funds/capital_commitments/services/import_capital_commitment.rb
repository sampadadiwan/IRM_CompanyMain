class ImportCapitalCommitment
  include Interactor
  STANDARD_HEADERS = ["Investor", "Fund", "Committed Amount", "Notes"].freeze
  def call
    if context.import_upload.present? && context.import_file.present?
      process_capital_commitments(context.import_file, context.import_upload)
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def process_capital_commitments(_file, import_upload)
    headers = context.headers
    custom_field_headers = headers - STANDARD_HEADERS

    data = context.data

    # Parse the XL rows
    package = Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Import Results") do |sheet|
        data.each_with_index do |row, idx|
          # skip header row
          next if idx.zero?

          process_row(headers, custom_field_headers, row, import_upload)
          # add row to results sheet
          sheet.add_row(row)
          # To indicate progress
          import_upload.save if (idx % 10).zero?
        end
      end
    end

    File.write("/tmp/import_result_#{import_upload.id}.xlsx", package.to_stream.read)
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
        capital_commitment.properties[cfh.underscore] = user_data[cfh]
      end
    end
  end
end
