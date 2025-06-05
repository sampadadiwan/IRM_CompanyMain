class ImportCapitalRemittancePayment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Capital Call", "Amount (Folio Currency)", "Currency", "Amount (Fund Currency)", "Folio No", "Virtual Bank Account", "Verified", "Reference No", "Payment Date", "Notes", "Update Only"].freeze

  step nil, delete: :create_custom_fields

  def initialize(**)
    super
    @capital_remittance_ids = {}
  end

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing capital_remittance_payment #{user_data}" }

    inputs = inputs(import_upload, user_data)
    fund, capital_call, investor, capital_commitment, capital_remittance, _folio_amount_cents, folio_currency, _update_only = inputs
    if fund && capital_call && investor && capital_commitment &&
       capital_remittance && folio_currency == capital_commitment.folio_currency

      create_or_update_capital_remittance_payment(inputs, user_data, custom_field_headers, import_upload)

    else
      raise "Fund not found" unless fund
      raise "Capital Call not found" unless capital_call
      raise "Capital Remittance not found" unless capital_remittance
      raise "Currency not same as commitment currency" unless folio_currency == capital_commitment.folio_currency
    end

    true
  end

  def create_or_update_capital_remittance_payment(inputs, user_data, custom_field_headers, import_upload)
    # Make the capital_remittance
    fund, _, _, _, capital_remittance, folio_amount_cents, _, _, _, update_only = inputs
    capital_remittance_payment = CapitalRemittancePayment.where(entity_id: fund.entity_id, fund:,
                                                                capital_remittance:,
                                                                folio_amount_cents:,
                                                                reference_no: user_data["Reference No"],
                                                                payment_date: user_data["Payment Date"]).first

    if update_only == "Yes"
      if capital_remittance_payment.present?
        # Update only, and we have a pre-existing capital_remittance_payment
        capital_remittance_payment.import_upload_id = import_upload.id
        save_crp(capital_remittance_payment, inputs, user_data, custom_field_headers)
      else
        # Update only, but we dont have a pre-existing capital_remittance_payment
        raise "Skipping: CapitalRemittancePayment not found for update"
      end
    elsif capital_remittance_payment.nil?
      capital_remittance_payment = CapitalRemittancePayment.new(import_upload_id: import_upload.id)
      save_crp(capital_remittance_payment, inputs, user_data, custom_field_headers)
    # No update, and we dont have a pre-existing capital_remittance_payment
    else
      # No update, but we have a pre-existing capital_remittance_payment
      raise "Skipping: CapitalRemittancePayment already exists"
    end

    # Add the capital_remittance to the set, so we can save them after all the payment numbers are rolled up
    @capital_remittance_ids[capital_remittance.id.to_s] = user_data["Verified"] == "Yes"
  end

  def save_crp(capital_remittance_payment, inputs, user_data, custom_field_headers)
    fund, _, _, _, capital_remittance, folio_amount_cents, _, amount_cents, convert_to_fund_currency, = inputs
    capital_remittance_payment.assign_attributes(entity_id: fund.entity_id, fund:,
                                                 capital_remittance:,
                                                 folio_amount_cents:,
                                                 amount_cents:,
                                                 notes: user_data["Notes"],
                                                 reference_no: user_data["Reference No"],
                                                 payment_date: user_data["Payment Date"],
                                                 convert_to_fund_currency:)

    setup_custom_fields(user_data, capital_remittance_payment, custom_field_headers)

    result = if capital_remittance_payment.new_record?
               CapitalRemittancePaymentCreate.call(capital_remittance_payment:)
             else
               CapitalRemittancePaymentUpdate.call(capital_remittance_payment:)
             end

    raise result[:errors] unless result.success?

    result.success?
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
    raise "Investor commitment not found for folio #{folio_id}" if folio_id.present? && capital_commitment.blank?

    capital_commitment = fund.capital_commitments.where(investor_id: investor.id, virtual_bank_account:).first if virtual_bank_account
    raise "Investor commitment not found for virtual bank account #{virtual_bank_account}" if virtual_bank_account.present? && capital_commitment.blank?

    capital_remittance = capital_call.capital_remittances.where(folio_id: capital_commitment.folio_id).first
    raise "Capital Remittance not found" unless capital_remittance

    folio_amount_cents = user_data["Amount (Folio Currency)"].to_d * 100
    amount_cents = user_data["Amount (Fund Currency)"].present? ? user_data["Amount (Fund Currency)"].to_d * 100 : 0
    folio_currency = user_data["Currency"]
    update_only = user_data["Update Only"]

    convert_to_fund_currency = true
    convert_to_fund_currency = false if user_data["Amount (Folio Currency)"].present? && user_data["Amount (Fund Currency)"].present?

    [fund, capital_call, investor, capital_commitment, capital_remittance, folio_amount_cents, folio_currency, amount_cents, convert_to_fund_currency, update_only]
  end

  def defer_counter_culture_updates
    true
  end

  def post_process(_ctx, import_upload:, **)
    # This had to be overridden as we need to pass the capital_remittance_ids to the job
    ImportCapitalRemittancePaymentsFixCountsJob.perform_later(import_upload.id, @capital_remittance_ids)
    true
  end
end
