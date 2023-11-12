class ImportCapitalCommittment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Folio Currency", "Committed Amount", "Fund Close", "Notes", "Folio No", "Unit Type", "Type", "Commitment Date", "Onboarding Completed", "From Currency", "To Currency", "Exchange Rate", "As Of", "KYC Full Name"].freeze

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
      status, msg = save_capital_commitment(user_data, import_upload, custom_field_headers)
      if status
        import_upload.processed_row_count += 1
      else
        import_upload.failed_row_count += 1
      end
      row << msg
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
    msg = ""
    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first
    raise "Fund not found" unless fund

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first
    raise "Investor not found" unless investor

    folio_id, unit_type, commitment_type, commitment_date, folio_currency, onboarding_completed = get_params(user_data)

    # binding.pry

    # Make the capital_commitment
    capital_commitment = CapitalCommitment.new(entity_id: import_upload.entity_id, folio_id:,
                                               fund_close: user_data["Fund Close"].strip,
                                               commitment_type:, commitment_date:,
                                               onboarding_completed:, imported: true,
                                               fund:, investor:, investor_name: investor.investor_name,
                                               folio_currency:, unit_type:, notes: user_data["Notes"])

    capital_commitment.folio_committed_amount = user_data["Committed Amount"].to_d

    capital_commitment.investor_kyc = get_kyc(user_data, investor, fund, capital_commitment, msg)

    setup_custom_fields(user_data, capital_commitment, custom_field_headers)
    setup_exchange_rate(capital_commitment, user_data) if capital_commitment.foreign_currency?

    valid, error_message = validate(capital_commitment)
    if valid
      capital_commitment.run_callbacks(:save) { false }
      capital_commitment.run_callbacks(:create) { false }
      @commitments << capital_commitment

      msg += " Success"
      [true, msg]
    else
      Rails.logger.debug { "Could not save commitment: #{error_message}" }
      [false, error_message]
    end
  end

  def get_kyc(user_data, investor, fund, _capital_commitment, _msg)
    kyc_full_name = user_data["KYC Full Name"]&.strip
    if kyc_full_name.present?
      fund.entity.investor_kycs.where(investor_id: investor.id, full_name: kyc_full_name).last

    else
      fund.entity.investor_kycs.where(investor_id: investor.id).last
    end
  end

  def validate(capital_commitment)
    if capital_commitment.valid?
      folio_already_exists = @commitments.any? { |c| c.folio_id == capital_commitment.folio_id && c.fund_id == capital_commitment.fund_id }
      return [false, "Duplicate Folio Id"] if folio_already_exists
    else
      return [false, capital_commitment.errors.full_messages]
    end

    [true, "Success"]
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

  def post_process(import_upload, _context)
    # Import it
    CapitalCommitment.import @commitments, on_duplicate_key_update: %i[commitment_type commitment_date folio_currency unit_type fund_close virtual_bank_account notes properties onboarding_completed]

    # Fix counters
    CapitalCommitment.counter_culture_fix_counts where: { entity_id: import_upload.entity_id }

    # Ensure ES is updated
    CapitalCommitmentIndex.import(CapitalCommitment.where(entity_id: import_upload.entity_id))

    fund_ids = @commitments.to_set(&:fund_id).to_a

    # Sometimes we import custom fields. Ensure custom fields get created
    @last_saved = import_upload.entity.funds.last.capital_commitments.last
    FormType.extract_from_db(@last_saved) if @last_saved

    Fund.where(id: fund_ids).find_each do |fund|
      # Compute the percentages
      fund.capital_commitments.last&.compute_percentage
      fund.save
    end
  end
end
