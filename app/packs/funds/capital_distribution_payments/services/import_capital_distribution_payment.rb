class ImportCapitalDistributionPayment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Capital Distribution", "Amount", "Payment Date", "Completed"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      if save_capital_distribution_payment(user_data, import_upload, custom_field_headers)
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

  def save_capital_distribution_payment(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_distribution_payment #{user_data}" }

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first
    capital_distribution = fund.capital_distributions.where(title: user_data["Capital Distribution"].strip).first
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first
    folio_id = user_data["Folio Id"]&.strip
    capital_commitment = fund.capital_commitments.where(investor_id: investor.id, folio_id:).first

    if fund && capital_distribution && investor

      # Make the capital_distribution_payment
      capital_distribution_payment = CapitalDistributionPayment.new(entity_id: import_upload.entity_id, fund:, capital_distribution:, investor:, capital_commitment:, payment_date: user_data["Payment Date"])

      capital_distribution_payment.folio_id = folio_id
      capital_distribution_payment.amount = user_data["Amount"]
      capital_distribution_payment.completed = user_data["Completed"] == "Yes"

      setup_custom_fields(user_data, capital_distribution_payment, custom_field_headers)

      capital_distribution_payment.save!

    else
      raise "Fund not found" unless fund
      raise "Capital Distribution not found" unless capital_distribution
      raise "Investor not found" unless investor
      raise "Capita Commitment not found" unless capital_commitment
    end
  end
end
