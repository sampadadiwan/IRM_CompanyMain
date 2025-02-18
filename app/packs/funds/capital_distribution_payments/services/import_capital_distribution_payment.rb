class ImportCapitalDistributionPayment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Capital Distribution", "Income", "Payment Date", "Completed", "Folio No", "Face Value For Redemption", "Reinvestment"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing capital_distribution_payment #{user_data}" }

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first
    raise "Fund not found" unless fund

    capital_distribution = fund.capital_distributions.where(title: user_data["Capital Distribution"].strip).first
    raise "Capital Distribution not found" unless capital_distribution

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    folio_id = user_data["Folio No"]&.to_s
    capital_commitment = fund.capital_commitments.where(investor_id: investor&.id, folio_id:).first

    if fund && capital_distribution && investor && capital_commitment

      # Make the capital_distribution_payment
      capital_distribution_payment = CapitalDistributionPayment.new(entity_id: import_upload.entity_id, fund:, capital_distribution:, investor:, investor_name: investor.investor_name, capital_commitment:, folio_id:, payment_date: user_data["Payment Date"])

      capital_distribution_payment.import_upload_id = import_upload.id
      capital_distribution_payment.folio_id = folio_id
      capital_distribution_payment.percentage = capital_commitment.percentage
      capital_distribution_payment.income = user_data["Income"]
      capital_distribution_payment.reinvestment = user_data["Reinvestment"]
      capital_distribution_payment.cost_of_investment = user_data["Face Value For Redemption"]
      capital_distribution_payment.completed = user_data["Completed"] == "Yes"

      setup_custom_fields(user_data, capital_distribution_payment, custom_field_headers)
      capital_distribution_payment.setup_distribution_fees

      result = CapitalDistributionPaymentCreate.call(capital_distribution_payment: capital_distribution_payment)
      raise result[:errors] unless result.success?

      result.success?

    else
      raise "Fund not found" unless fund
      raise "Capital Distribution not found" unless capital_distribution
      raise "Investor not found" unless investor
      raise "Capital Commitment not found" unless capital_commitment
    end
  end

  def defer_counter_culture_updates
    true
  end
end
