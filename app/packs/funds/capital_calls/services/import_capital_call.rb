class ImportCapitalCall < ImportUtil
  STANDARD_HEADERS = ["Fund", "Name", "Percentage Called", "Due Date", "Call Date", "Fund Closes", "Generate Remittances", "Remittances Verified", "Type"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def pre_process(import_upload, context)
    @exchange_rates = get_exchange_rates(context.import_file, import_upload)
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
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
    rescue ActiveRecord::Deadlocked => e
      raise e
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
        generate_remittances = user_data["Generate Remittances"]&.strip&.downcase == "yes"
        generate_remittances_verified = user_data["Remittances Verified"]&.strip&.downcase == "yes"
        fund_closes = user_data["Fund Closes"] ? user_data["Fund Closes"].strip.split(",") : ["All"]

        # Make the capital_call
        capital_call = CapitalCall.new(entity_id: import_upload.entity_id, name:,
                                       fund:, due_date: user_data["Due Date"],
                                       call_date: user_data["Call Date"],
                                       fund_closes:, commitment_type: user_data["Type"],
                                       percentage_called: user_data["Percentage Called"],
                                       manual_generation: true,
                                       generate_remittances:, generate_remittances_verified:)

        setup_custom_fields(user_data, capital_call, custom_field_headers)

        check_exchange_rate(capital_call)

        capital_call.save!
        Rails.logger.debug "Saved CapitalCall"
      end
    else
      raise "Fund not found"
    end
  end

  def check_exchange_rate(capital_call)
    # We need to setup the commitments for the exchange rate
    er_user_data = @exchange_rates.find { |er| er["As Of"] == capital_call.call_date }
    if er_user_data.present?
      exchange_rate = setup_exchange_rate(capital_call, er_user_data)
      Rails.logger.debug { "Created #{exchange_rate}" }
    else
      Rails.logger.debug { "No ExchangeRate specified for Call #{capital_call}" }
    end
  end
end
