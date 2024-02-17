class ImportCapitalRemittancePayment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Capital Call", "Amount", "Currency", "Folio No", "Virtual Bank Account", "Verified", "Reference No", "Payment Date", "Notes", "Update Only"].freeze

  attr_accessor :fund_ids

  def initialize(params)
    super(params)
    @fund_ids = Set.new
  end

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
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

  def post_process(import_upload, _context)
    CapitalRemittancePayment.counter_culture_fix_counts where: { entity_id: import_upload.entity_id }
    CapitalRemittance.counter_culture_fix_counts where: { entity_id: import_upload.entity_id }
  end

  def save_capital_remittance_payment(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_remittance_payment #{user_data}" }

    inputs = inputs(import_upload, user_data)
    fund, capital_call, investor, capital_commitment, capital_remittance, _folio_amount_cents, folio_currency, _update_only = inputs
    if fund && capital_call && investor && capital_commitment &&
       capital_remittance && folio_currency == capital_commitment.folio_currency

      @fund_ids.add(fund.id)

      create_or_update_capital_remittance_payment(inputs, user_data, custom_field_headers, import_upload)

    else
      raise "Fund not found" unless fund
      raise "Capital Call not found" unless capital_call
      raise "Capital Remittance not found" unless capital_remittance
      raise "Currency not same as commitment currency" unless folio_currency == capital_commitment.folio_currency
    end
  end

  def create_or_update_capital_remittance_payment(inputs, user_data, custom_field_headers, import_upload)
    # Make the capital_remittance
    fund, _capital_call, _investor, _capital_commitment, capital_remittance, folio_amount_cents, _folio_currency, update_only = inputs
    capital_remittance_payment = CapitalRemittancePayment.where(entity_id: fund.entity_id, fund:,
                                                                capital_remittance:,
                                                                folio_amount_cents:,
                                                                reference_no: user_data["Reference No"],
                                                                payment_date: user_data["Payment Date"]).first
    if capital_remittance_payment.present? && update_only&.downcase == "yes"
      capital_remittance_payment.import_upload_id = import_upload.id
      save_crp(capital_remittance_payment, inputs, user_data, custom_field_headers)
    elsif capital_remittance_payment.nil?
      raise "Capital Remittance Payment not found" if update_only&.downcase == "yes"

      capital_remittance_payment = CapitalRemittancePayment.new(import_upload_id: import_upload.id)
      save_crp(capital_remittance_payment, inputs, user_data, custom_field_headers)
    else
      raise "Skipping: CapitalRemittancePayment already exists"
    end

    # We need to reload the capital_remittance, as the capital_remittance_payment counter caches would have updated the capital_remittance
    capital_remittance.reload
    capital_remittance.verified = user_data["Verified"] == "Yes"
    CapitalRemittanceUpdate.call(capital_remittance:)
  end

  def save_crp(capital_remittance_payment, inputs, user_data, custom_field_headers)
    fund, _capital_call, _investor, _capital_commitment, capital_remittance, folio_amount_cents, _folio_currency, _update_only = inputs
    capital_remittance_payment.assign_attributes(entity_id: fund.entity_id, fund:,
                                                 capital_remittance:,
                                                 folio_amount_cents:,
                                                 notes: user_data["Notes"],
                                                 reference_no: user_data["Reference No"],
                                                 payment_date: user_data["Payment Date"])

    setup_custom_fields(user_data, capital_remittance_payment, custom_field_headers)

    capital_remittance_payment.save!
  end

  def inputs(import_upload, user_data)
    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first
    raise "Fund not found" unless fund

    capital_call = fund.capital_calls.where(name: user_data["Capital Call"]).first
    raise "Capital Call not found" unless capital_call

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    raise "Investor not found" unless investor

    # One of the 2 should be present folio_id or virtual_bank_account
    folio_id = user_data["Folio No"]&.to_s
    virtual_bank_account = user_data["Virtual Bank Account"]&.to_s

    raise "Folio No or Virtual Bank Account must be specified" if folio_id.blank? && virtual_bank_account.blank?

    # Find the capital_commitment from either the folio_id or virtual_bank_account
    capital_commitment = fund.capital_commitments.where(investor_id: investor.id, folio_id:).first if folio_id
    capital_commitment = fund.capital_commitments.where(investor_id: investor.id, virtual_bank_account:).first if virtual_bank_account
    raise "Investor commitment not found" unless capital_commitment

    capital_remittance = capital_call.capital_remittances.where(folio_id: capital_commitment.folio_id).first
    raise "Capital Remittance not found" unless capital_remittance

    folio_amount_cents = user_data["Amount"].to_d * 100
    folio_currency = user_data["Currency"]
    update_only = user_data["Update Only"]

    [fund, capital_call, investor, capital_commitment, capital_remittance, folio_amount_cents, folio_currency, update_only]
  end
end
