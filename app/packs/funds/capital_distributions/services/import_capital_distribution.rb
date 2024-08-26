class ImportCapitalDistribution < ImportUtil
  STANDARD_HEADERS = ["Fund", "Type", "Title", "Gross", "Date", "Generate Payments", "Payments Paid", "Reinvestment", "Folio No", "Distribution Basis", "Face Value For Redemption"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing capital_distribution #{user_data}" }

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first

    if fund
      title = user_data["Title"]
      if CapitalDistribution.exists?(entity_id: import_upload.entity_id, fund:, title:)
        raise "Capital Distribution Already Present"
      else

        generate_payments = user_data["Generate Payments"]&.downcase == "yes"
        generate_payments_paid = user_data["Payments Paid"]&.downcase == "yes"

        # Make the capital_distribution
        capital_distribution = CapitalDistribution.new(entity_id: import_upload.entity_id, title:,
                                                       fund:, distribution_date: user_data["Date"],
                                                       manual_generation: true,

                                                       commitment_type: user_data["Type"],
                                                       generate_payments:, generate_payments_paid:)

        if capital_distribution.CoInvest?
          # If this is a co_invest, then we need to set the commitment
          capital_distribution.capital_commitment = capital_distribution.fund.capital_commitments.where(folio_id: user_data["Folio No"]).first
        end
        capital_distribution.import_upload_id = import_upload.id
        capital_distribution.gross_amount = user_data["Gross"]
        capital_distribution.cost_of_investment = user_data["Face Value For Redemption"]
        capital_distribution.reinvestment = user_data["Reinvestment"]
        capital_distribution.distribution_on = user_data["Distribution Basis"].presence || "Commitment Percentage"

        setup_custom_fields(user_data, capital_distribution, custom_field_headers)

        # We need to setup the commitments for the exchange rate
        setup_exchange_rate(capital_distribution, user_data) if user_data["From Currency"].present?

        capital_distribution.save!
      end
    else
      raise "Fund not found"
    end
  end
end
