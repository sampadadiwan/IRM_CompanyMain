class ImportCapitalDistributionPayment < ImportUtil
  STANDARD_HEADERS = ["Fund", "Capital Distribution", "Income", "Payment Date", "Completed", "Folio No", "Face Value For Redemption", "Reinvestment"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  # Older templates may still carry a Stakeholder column - ignore it so it does not become a custom field
  def ignore_headers
    ["Stakeholder"]
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing capital_distribution_payment #{user_data}" }

    # Get the Fund
    fund_name = user_data["Fund"]
    fund = import_upload.entity.funds.where(name: fund_name).first
    raise "Fund not found: #{fund_name}" unless fund

    # cell(required: true) rather than a bare strip - a blank cell used to raise
    # "undefined method 'strip' for nil" instead of naming the column
    distribution_title = cell(user_data, "Capital Distribution", required: true).strip
    capital_distribution = fund.capital_distributions.where(title: distribution_title).first
    raise "Capital Distribution not found in fund #{fund.name}: #{distribution_title}" unless capital_distribution

    # Find the capital commitment purely via the folio ID - the investor is derived from the commitment
    folio_id = cell(user_data, "Folio No", required: true).to_s
    capital_commitment = fund.capital_commitments.where(folio_id:).first
    raise "Capital Commitment not found for fund #{fund.name}, folio #{folio_id}" unless capital_commitment

    # A commitment with no investor cannot be paid out - without this the row fell
    # through every guard below and the results sheet showed a bare "Error"
    investor = capital_commitment.investor
    raise "Investor not found for folio #{folio_id} in fund #{fund.name}" unless investor

    if fund && capital_distribution && capital_commitment && investor

      # Make the capital_distribution_payment
      capital_distribution_payment = CapitalDistributionPayment.new(entity_id: import_upload.entity_id, fund:, capital_distribution:, investor:, investor_name: investor.investor_name, capital_commitment:, folio_id:, payment_date: user_data["Payment Date"])

      capital_distribution_payment.import_upload_id = import_upload.id
      capital_distribution_payment.folio_id = folio_id
      capital_distribution_payment.percentage = capital_commitment.percentage
      capital_distribution_payment.income = user_data["Income"].to_d
      capital_distribution_payment.reinvestment = user_data["Reinvestment"]
      capital_distribution_payment.cost_of_investment = user_data["Face Value For Redemption"]
      capital_distribution_payment.completed = user_data["Completed"] == "Yes"

      setup_custom_fields(user_data, capital_distribution_payment, custom_field_headers)
      capital_distribution_payment.setup_distribution_fees

      result = CapitalDistributionPaymentCreate.call(capital_distribution_payment: capital_distribution_payment)
      raise result[:errors] unless result.success?

      result.success?

    else
      # Unreachable - every input is guarded above - but kept as a backstop so a
      # future edit cannot silently return nil and produce an unexplained "Error"
      raise "Fund not found: #{fund_name}" unless fund
      raise "Capital Distribution not found: #{distribution_title}" unless capital_distribution
      raise "Capital Commitment not found for folio #{folio_id}" unless capital_commitment

      raise "Investor not found for folio #{folio_id}"
    end
  end

  def defer_counter_culture_updates
    true
  end
end
