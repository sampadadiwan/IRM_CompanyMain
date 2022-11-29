class ImportCapitalCall < ImportUtil
  STANDARD_HEADERS = ["Fund", "Name", "Percentage Called", "Due Date"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      if save_capital_call(user_data, import_upload, custom_field_headers)
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

  def save_capital_call(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_call #{user_data}" }

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first

    if fund
      name = user_data["Name"].strip
      if CapitalCall.exists?(entity_id: import_upload.entity_id, fund:, name:)
        raise "Capital Call Already Present"
      else

        # Make the capital_call
        capital_call = CapitalCall.new(entity_id: import_upload.entity_id, name:,
                                       fund:, due_date: user_data["Due Date"],
                                       percentage_called: user_data["Percentage Called"])

        setup_custom_fields(user_data, capital_call, custom_field_headers)

        capital_call.save
      end
    else
      raise "Fund not found"
    end
  end

  def setup_custom_fields(user_data, capital_call, custom_field_headers)
    # Were any custom fields passed in ? Set them up
    if custom_field_headers.length.positive?
      capital_call.properties ||= {}
      custom_field_headers.each do |cfh|
        capital_call.properties[cfh.parameterize.underscore] = user_data[cfh]
      end
    end
  end
end
