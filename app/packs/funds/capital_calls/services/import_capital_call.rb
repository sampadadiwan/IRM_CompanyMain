class ImportCapitalCall < ImportUtil
  STANDARD_HEADERS = ["Fund", "Name", "Percentage Called", "Due Date", "Call Date", "Fund Closes", "Generate Remittances", "Remittances Verified", "Type"].freeze

  def standard_headers
    STANDARD_HEADERS
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

        # We need to adjust the commitments for the exchange rate
        exchange_rates_commitment_adjustment(capital_call)

        capital_call.save!
      end
    else
      raise "Fund not found"
    end
  end

  # We need to ensure the exchange rate just prior to the call dues_date, is applied to the capital commitments
  # This is so that the called amounts are from the adjusted commitments
  def exchange_rates_commitment_adjustment(capital_call)
    # For each folio currency used in the fund, apply it to adjust the commitments
    folio_currencies = capital_call.fund.capital_commitments.pluck(:folio_currency).uniq
    fund_currency = capital_call.fund.currency
    folio_currencies.each do |folio_currency|
      if folio_currency != fund_currency
        exchange_rate = capital_call.entity.exchange_rates.where(from: folio_currency, to: fund_currency, as_of: ..capital_call.due_date).order(as_of: :asc).last
        ExchangeRateCommitmentAdjustmentJob.perform_now(exchange_rate.id)
      end
    end
  end
end
