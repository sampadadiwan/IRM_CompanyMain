class ImportCapitalDistribution < ImportUtil
  STANDARD_HEADERS = ["Fund", "Title", "Gross", "Carry", "Date", "Generate Payments", "Payments Paid"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      if save_capital_distribution(user_data, import_upload, custom_field_headers)
        import_upload.processed_row_count += 1
        row << "Success"
      else
        import_upload.failed_row_count += 1
        row << "Error"
      end
    rescue StandardError => e
      Rails.logger.debug Rails.env.test? ? e.message : e.backtrace
      row << "Error #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  def save_capital_distribution(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_distribution #{user_data}" }

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first

    if fund
      title = user_data["Title"].strip
      if CapitalDistribution.exists?(entity_id: import_upload.entity_id, fund:, title:)
        raise "Capital Distribution Already Present"
      else

        generate_payments = user_data["Generate Payments"]&.strip&.downcase == "yes"
        generate_payments_paid = user_data["Payments Paid"]&.strip&.downcase == "yes"

        # Make the capital_distribution
        capital_distribution = CapitalDistribution.new(entity_id: import_upload.entity_id, title:,
                                                       fund:, distribution_date: user_data["Date"],
                                                       manual_generation: true,
                                                       generate_payments:, generate_payments_paid:)

        capital_distribution.gross_amount = user_data["Gross"]
        capital_distribution.carry = user_data["Carry"]

        setup_custom_fields(user_data, capital_distribution, custom_field_headers)

        capital_distribution.save!
      end
    else
      raise "Fund not found"
    end
  end
end
