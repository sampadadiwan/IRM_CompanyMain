class ImportCapitalRemittancePayment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Capital Call", "Collected Amount", "Folio No", "Verified", "Reference No", "Payment Date"].freeze

  attr_accessor :fund_ids

  def initialize(params)
    super(params)
    @fund_ids = Set.new
  end

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      if save_capital_remittance_payment(user_data, import_upload, custom_field_headers)
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

  def post_process(_import_upload)
    CapitalRemittance.counter_culture_fix_counts where: { 'capital_remittances.fund_id': @fund_ids.to_a }
  end

  def save_capital_remittance_payment(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_remittance_payment #{user_data}" }

    fund, capital_call, investor, capital_commitment, capital_remittance, collected_amount_cents = inputs(import_upload, user_data)

    if fund && capital_call && investor && capital_commitment && capital_remittance
      @fund_ids.add(fund.id)

      # Make the capital_remittance
      capital_remittance_payment = CapitalRemittancePayment.new(entity_id: fund.entity_id, fund:,
                                                                capital_remittance:,
                                                                amount_cents: collected_amount_cents,
                                                                reference_no: user_data["Reference No"],
                                                                payment_date: user_data["Payment Date"])

      setup_custom_fields(user_data, capital_remittance_payment, custom_field_headers)

      capital_remittance_payment.save!

      capital_remittance.verified = user_data["Verified"] == "Yes"
      capital_remittance.save!

    else
      raise "Fund not found" unless fund
      raise "Capital Call not found" unless capital_call
      raise "Capital Remittance not found" unless capital_remittance
    end
  end

  def inputs(import_upload, user_data)
    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first
    raise "Fund not found" unless fund

    capital_call = fund.capital_calls.where(name: user_data["Capital Call"].strip).first
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first
    raise "Investor not found" unless investor

    folio_id = user_data["Folio No"]&.to_s&.strip
    raise "Folio No not found" unless folio_id

    capital_commitment = fund.capital_commitments.where(investor_id: investor.id, folio_id:).first
    raise "Investor commitment not found" unless capital_commitment

    capital_remittance = capital_call.capital_remittances.where(folio_id:).first
    collected_amount_cents = user_data["Collected Amount"].to_d * 100

    [fund, capital_call, investor, capital_commitment, capital_remittance, collected_amount_cents]
  end
end
