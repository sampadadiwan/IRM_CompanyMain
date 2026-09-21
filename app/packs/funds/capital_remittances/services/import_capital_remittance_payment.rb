class ImportCapitalRemittancePayment < ImportUtil
  STANDARD_HEADERS = ["Fund", "Capital Call", "Amount (Folio Currency)", "Currency", "Amount (Fund Currency)", "Folio No", "Virtual Bank Account", "Verified", "Reference No", "Payment Date", "Notes", "Update Only"].freeze

  step nil, delete: :create_custom_fields

  # Capped so the aggregated warning stays inside user_alerts.message (a 255-char VARCHAR)
  MAX_NAMES_IN_ALERT = 5

  def initialize(**)
    super
    @capital_remittance_ids = {}
    @unapproved_call_names = Set.new
    @conflicting_folio_ids = Set.new
  end

  def standard_headers
    STANDARD_HEADERS
  end

  # Older templates may still carry a Stakeholder column - ignore it so it does not become a custom field
  def ignore_headers
    ["Stakeholder"]
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing capital_remittance_payment #{user_data}" }

    inputs = inputs(import_upload, user_data)
    fund, capital_call, investor, capital_commitment, capital_remittance, _folio_amount_cents, folio_currency, _update_only = inputs
    if fund && capital_call && investor && capital_commitment &&
       capital_remittance && folio_currency == capital_commitment.folio_currency

      create_or_update_capital_remittance_payment(inputs, user_data, custom_field_headers, import_upload)

    else
      # Unreachable - inputs raises on each of these - but kept so a future edit
      # cannot fall through and leave the row with an unexplained "Error"
      raise "Fund not found: #{user_data['Fund']}" unless fund
      raise "Capital Call not found: #{user_data['Capital Call']}" unless capital_call
      raise "Capital Remittance not found for folio #{capital_commitment&.folio_id}" unless capital_remittance
      raise "Amount is in #{folio_currency} but folio #{capital_commitment.folio_id} is held in #{capital_commitment.folio_currency}" unless folio_currency == capital_commitment.folio_currency
    end

    true
  end

  # `verified` lives on the CapitalRemittance, not on the payment, and
  # CapitalRemittance#verified_requires_approval refuses it while the call is unapproved - the same
  # rule that greys out the interactive Verify action. Decide it here, where there is still a row to
  # attach the explanation to: the flag itself is applied much later by
  # ImportCapitalRemittancePaymentsFixCountsJob, long after the results sheet has been written and
  # attached, which is why a rejected flip used to vanish without a trace.
  #
  # The payment is a fact and is still imported - only the verification is withheld. Returning
  # false rather than leaving the flag untouched is safe: CapitalRemittancePayment's
  # after_commit :unverify_remittance has already set it to false for this remittance.
  def verified_requested?(user_data, capital_call)
    return false unless user_data["Verified"].to_s.casecmp?("yes")
    return true if capital_call.approved?

    @unapproved_call_names << capital_call.name
    warn_row("Payment imported, but the remittance was not marked Verified: capital call " \
             "'#{capital_call.name}' is not approved. Approve the call, then verify its remittances.")
    false
  end

  # `verified` belongs to the remittance, but the sheet carries the column once per payment row, so
  # several rows can disagree about the same folio. This used to be a plain assignment keyed on the
  # remittance, so the last row silently won and a "No" typed below a "Yes" cancelled a
  # verification with nothing to show for it.
  #
  # Rows that agree are applied. Rows that disagree leave the remittance unverified and say so:
  # verifying is the irreversible direction - it emails investors and lets units be allocated -
  # while the opposite is one click of Verify Pending Remittances.
  def record_verified_request(capital_remittance, user_data, capital_call)
    key = capital_remittance.id.to_s
    requested = verified_requested?(user_data, capital_call)

    return @capital_remittance_ids[key] = requested unless @capital_remittance_ids.key?(key)
    return if @capital_remittance_ids[key] == requested

    @capital_remittance_ids[key] = false
    @conflicting_folio_ids << capital_remittance.folio_id
    warn_row("Payment imported, but the remittance was left unverified: the payment rows for folio " \
             "#{capital_remittance.folio_id} in call '#{capital_call.name}' disagree about Verified. " \
             "Use the same value on every row for a folio, then verify the remittance.")
  end

  def create_or_update_capital_remittance_payment(inputs, user_data, custom_field_headers, import_upload)
    # Make the capital_remittance
    fund, capital_call, _, capital_commitment, capital_remittance, folio_amount_cents, _, _, _, update_only = inputs
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
        raise "Skipping: no payment found to update for folio #{capital_commitment.folio_id} in call #{capital_call.name}"
      end
    elsif capital_remittance_payment.nil?
      capital_remittance_payment = CapitalRemittancePayment.new(import_upload_id: import_upload.id)
      save_crp(capital_remittance_payment, inputs, user_data, custom_field_headers)
    # No update, and we dont have a pre-existing capital_remittance_payment
    else
      # No update, but we have a pre-existing capital_remittance_payment
      raise "Skipping: a payment for folio #{capital_commitment.folio_id} in call #{capital_call.name} on #{user_data['Payment Date']} already exists"
    end

    # Add the capital_remittance to the set, so we can save them after all the payment numbers are rolled up
    record_verified_request(capital_remittance, user_data, capital_call)
  end

  def save_crp(capital_remittance_payment, inputs, user_data, custom_field_headers)
    fund, _, _, _, capital_remittance, folio_amount_cents, _, amount_cents, convert_to_fund_currency, = inputs
    capital_remittance_payment.assign_attributes(entity_id: fund.entity_id, fund:,
                                                 capital_remittance:,
                                                 folio_amount_cents:,
                                                 amount_cents:,
                                                 investor_id: capital_remittance.investor_id,
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
    raise "Fund not found: #{user_data['Fund']}" unless fund

    capital_call = fund.capital_calls.where(name: user_data["Capital Call"]).first
    raise "Capital Call not found in fund #{fund.name}: #{user_data['Capital Call']}" unless capital_call

    raise "Payment Date is mandatory" if user_data["Payment Date"].blank?

    # One of the 2 should be present folio_id or virtual_bank_account
    folio_id = user_data["Folio No"]&.to_s
    virtual_bank_account = user_data["Virtual Bank Account"]&.to_s

    raise "Folio No or Virtual Bank Account must be specified" if folio_id.blank? && virtual_bank_account.blank?

    # Find the capital_commitment from either the folio_id or virtual_bank_account
    capital_commitment = fund.capital_commitments.where(folio_id:).first if folio_id
    raise "Commitment not found for folio #{folio_id}" if folio_id.present? && capital_commitment.blank?

    capital_commitment = fund.capital_commitments.where(virtual_bank_account:).first if virtual_bank_account
    raise "Commitment not found for virtual bank account #{virtual_bank_account}" if virtual_bank_account.present? && capital_commitment.blank?

    # The investor is derived from the commitment, not from the sheet
    investor = capital_commitment.investor

    capital_remittance = capital_call.capital_remittances.where(folio_id: capital_commitment.folio_id).first
    raise "No remittance for folio #{capital_commitment.folio_id} in call #{capital_call.name} - generate the remittances first" unless capital_remittance

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
    warn_about_skipped_verifications(import_upload)
    # This had to be overridden as we need to pass the capital_remittance_ids to the job
    ImportCapitalRemittancePaymentsFixCountsJob.perform_later(import_upload.id, @capital_remittance_ids)
    true
  end

  # Aggregate counterpart to the per-row warn_row calls above, on the two channels the import
  # summary screen actually shows: import_upload.status (ImportUploadJob only writes "Completed"
  # over a blank status, so this survives) and the standard on-screen warning alert - the same
  # channel ImportCapitalCommitment#warn_about_unsubscribed_investors uses. The import itself still
  # succeeds: failed_row_count stays at zero and every payment is saved.
  def warn_about_skipped_verifications(import_upload)
    reasons = []
    if @unapproved_call_names.any?
      reasons << "These capital calls are not approved: #{summarise(@unapproved_call_names)} - " \
                 "approve each call, then verify its remittances."
    end
    if @conflicting_folio_ids.any?
      reasons << "These folios have payment rows that disagree about Verified: " \
                 "#{summarise(@conflicting_folio_ids)} - use one value per folio, then verify those remittances."
    end
    return if reasons.empty?

    message = "Payments imported, but some remittances were not marked Verified. #{reasons.join(' ')}"
    import_upload.status = message
    import_upload.save
    # Persisted via create! rather than new+broadcast so the warning is auditable
    UserAlert.create!(user_id: import_upload.user_id, entity_id: import_upload.entity_id,
                      level: "warning", message: message.truncate(255))
  end

  def summarise(names)
    listed = names.to_a.sort
    text = listed.first(MAX_NAMES_IN_ALERT).join(", ")
    text += " and #{listed.size - MAX_NAMES_IN_ALERT} more" if listed.size > MAX_NAMES_IN_ALERT
    text
  end
end
