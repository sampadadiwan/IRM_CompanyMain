class ImportCapitalCommitment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Folio Currency", "Committed Amount (Folio Currency)", "Committed Amount (Fund Currency)", "Fund Close", "Notes", "Folio No", "Unit Type", "Commitment Date", "Onboarding Completed", "From Currency", "To Currency", "Exchange Rate", "As Of", "Kyc Investing Entity", "Investor Signatory Emails", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing capital_commitment #{user_data}" }
    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first
    raise "Fund not found" unless fund

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    raise "Investor not found" unless investor

    update_only = user_data["Update Only"]
    folio_id, _, _, folio_currency, = get_params(user_data)
    capital_commitment = CapitalCommitment.where(entity_id: import_upload.entity_id, folio_id:, fund_id: fund.id, investor_id: investor.id).first

    if update_only == "Yes"
      if capital_commitment.present?
        # Update only, and we have a pre-existing capital_commitment
        save_kyc(fund, capital_commitment, import_upload, investor, user_data, custom_field_headers)
      else
        # Update only, but we dont have a pre-existing capital_commitment
        raise "Capital Commitment not found for #{folio_id}"
      end
    elsif capital_commitment.nil?
      capital_commitment = CapitalCommitment.new(entity_id: import_upload.entity_id, folio_id:, fund:, folio_currency:)
      capital_commitment.folio_committed_amount = user_data["Committed Amount (Folio Currency)"].to_d
      # This could be blank, in which case it will be converted from the folio currency to the fund currency
      capital_commitment.committed_amount = user_data["Committed Amount (Fund Currency)"].to_d
      # Save the capital commitment
      save_kyc(fund, capital_commitment, import_upload, investor, user_data, custom_field_headers)
    # No update, and we dont have a pre-existing capital_commitment
    else
      # No update, but we have a pre-existing capital_commitment
      raise "Capital Commitment already exists for #{folio_id}"
    end
    true
  end

  def save_kyc(fund, capital_commitment, import_upload, investor, user_data, custom_field_headers)
    _, unit_type, commitment_date, _, onboarding_completed = get_params(user_data)
    capital_commitment.assign_attributes(fund_close: user_data["Fund Close"], commitment_date:,
                                         onboarding_completed:, imported: true, investor:,
                                         investor_name: investor.investor_name, unit_type:,
                                         import_upload_id: import_upload.id, notes: user_data["Notes"],
                                         esign_emails: user_data["Investor Signatory Emails"])

    get_kyc(user_data, investor, fund, capital_commitment)

    setup_custom_fields(user_data, capital_commitment, custom_field_headers)
    setup_exchange_rate(capital_commitment, user_data) if capital_commitment.foreign_currency?

    result = if capital_commitment.new_record?
               CapitalCommitmentCreate.call(capital_commitment:, import_upload:)
             else
               CapitalCommitmentUpdate.call(capital_commitment:, import_upload:)
             end

    raise result[:errors] unless result.success?

    result.success?
  end

  def get_kyc(user_data, investor, fund, capital_commitment)
    kyc_full_name = user_data["Kyc Investing Entity"]
    if kyc_full_name.present?
      kyc = fund.entity.investor_kycs.where(investor_id: investor.id, full_name: kyc_full_name).last
      raise "KYC not found" unless kyc
    else
      kyc = fund.entity.investor_kycs.where(investor_id: investor.id).last
    end

    if kyc
      capital_commitment.investor_kyc = kyc
      # Default the esign emails to the kyc esign emails
      capital_commitment.esign_emails ||= kyc.esign_emails
    end
  end

  def get_params(user_data)
    folio_id = user_data["Folio No"].presence
    unit_type = user_data["Unit Type"].presence
    commitment_date = user_data["Commitment Date"].presence
    folio_currency = user_data["Folio Currency"].presence
    onboarding_completed = user_data["Onboarding Completed"] == "Yes"

    [folio_id, unit_type, commitment_date, folio_currency, onboarding_completed]
  end

  def post_process(ctx, import_upload:, **)
    super
    # Recompute the percentages
    # Find one capital commitment per fund
    import_upload.reload
    import_upload.imported_data
                 .group_by(&:fund_id)
                 .each_value do |ccs_of_fund|
      # Pick one cc from this fund to trigger compute_percentage for the whole fund
      ccs_of_fund.first&.compute_percentage
    end
    last_cc = import_upload.reload.imported_data.last
    last_cc&.compute_percentage
    # Create remittances if required
    import_upload.imported_data.each do |capital_commitment|
      CapitalCommitmentRemittanceJob.perform_now(capital_commitment.id) if capital_commitment.fund.capital_calls.count.positive?

      capital_commitment.grant_access_to_fund
    end
    true
  end

  def defer_counter_culture_updates
    true
  end
end
