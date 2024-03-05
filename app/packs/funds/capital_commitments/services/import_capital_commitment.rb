class ImportCapitalCommitment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Folio Currency", "Committed Amount", "Fund Close", "Notes", "Folio No", "Unit Type", "Type", "Commitment Date", "Onboarding Completed", "From Currency", "To Currency", "Exchange Rate", "As Of", "Kyc Investing Entity", "Investor Signatory Emails", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(params)
    super(params)
    @commitments = []
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      status = save_capital_commitment(user_data, import_upload, custom_field_headers)
      if status
        import_upload.processed_row_count += 1
      else
        import_upload.failed_row_count += 1
      end
    rescue ActiveRecord::Deadlocked => e
      raise e
    rescue StandardError => e
      Rails.logger.debug e.backtrace
      Rails.logger.debug { "Error #{e.message}" }
      row << "Error #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  def save_capital_commitment(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_commitment #{user_data}" }
    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first
    raise "Fund not found" unless fund

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    raise "Investor not found" unless investor

    update_only = user_data["Update Only"]
    folio_id, unit_type, commitment_type, commitment_date, folio_currency, onboarding_completed = get_params(user_data)

    if update_only.present? && %w[yes y true].include?(update_only.downcase)
      capital_commitment = CapitalCommitment.where(entity_id: import_upload.entity_id, folio_id:, fund_id: fund.id, investor_id: investor.id).first
      raise "Capital Commitment not found for #{folio_id}" unless capital_commitment
    else
      # Make the capital_commitment
      capital_commitment = CapitalCommitment.new(entity_id: import_upload.entity_id, folio_id:, fund:, folio_currency:)
      capital_commitment.folio_committed_amount = user_data["Committed Amount"].to_d
    end

    capital_commitment.assign_attributes(fund_close: user_data["Fund Close"], commitment_type:, commitment_date:,
                                         onboarding_completed:, imported: true, investor:,
                                         investor_name: investor.investor_name, unit_type:,
                                         import_upload_id: import_upload.id, notes: user_data["Notes"],
                                         esign_emails: user_data["Investor Signatory Emails"])

    get_kyc(user_data, investor, fund, capital_commitment)

    setup_custom_fields(user_data, capital_commitment, custom_field_headers)
    setup_exchange_rate(capital_commitment, user_data) if capital_commitment.foreign_currency?

    result = if capital_commitment.new_record?
               CapitalCommitmentCreate.call(capital_commitment:)
             else
               CapitalCommitmentUpdate.call(capital_commitment:)
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
    commitment_type = user_data["Type"].presence
    commitment_date = user_data["Commitment Date"].presence
    folio_currency = user_data["Folio Currency"].presence
    onboarding_completed = user_data["Onboarding Completed"] == "Yes"

    [folio_id, unit_type, commitment_type, commitment_date, folio_currency, onboarding_completed]
  end
end
