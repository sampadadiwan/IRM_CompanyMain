class ImportCapitalCommittment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Folio Currency", "Committed Amount", "Fund Close", "Notes", "Folio No", "Unit Type", "Type", "Commitment Date", "Onboarding Completed", "From Currency", "To Currency", "Exchange Rate", "As Of"].freeze

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

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first

    folio_id, unit_type, commitment_type, commitment_date, folio_currency, onboarding_completed = get_params(user_data)

    if fund && investor
      # Make the capital_commitment
      capital_commitment = CapitalCommitment.new(entity_id: import_upload.entity_id, folio_id:,
                                                 fund_close: user_data["Fund Close"].strip,
                                                 commitment_type:, commitment_date:,
                                                 onboarding_completed:, imported: true,
                                                 fund:, investor:, investor_name: investor.investor_name,
                                                 folio_currency:, unit_type:, notes: user_data["Notes"])

      capital_commitment.folio_committed_amount = user_data["Committed Amount"].to_d
      capital_commitment.investor_kyc = fund.entity.investor_kycs.where(investor_id: investor.id).last

      setup_custom_fields(user_data, capital_commitment, custom_field_headers)
      setup_exchange_rate(capital_commitment, user_data) if capital_commitment.foreign_currency?

      if capital_commitment.valid?

        capital_commitment.run_callbacks(:save) { false }
        capital_commitment.run_callbacks(:create) { false }
        @commitments << capital_commitment

        [true, "Success"]
      else
        Rails.logger.debug { "Could not save commitment: #{capital_commitment.errors.full_messages}" }
        [false, capital_commitment.errors.full_messages]
      end
    elsif fund
      [false, "Investor not found"]
    else
      [false, "Fund not found"]
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

  def post_process(import_upload, _context)
    # Import it
    CapitalCommitment.import @commitments, on_duplicate_key_update: %i[commitment_type commitment_date folio_currency unit_type fund_close virtual_bank_account notes properties]
    # Fix counters
    CapitalCommitment.counter_culture_fix_counts where: { entity_id: import_upload.entity_id }
    # Ensure ES is updated
    CapitalCommitmentIndex.import(CapitalCommitment.where(entity_id: import_upload.entity_id))

    fund_ids = @commitments.collect(&:fund_id).to_set.to_a

    # Sometimes we import custom fields. Ensure custom fields get created
    @last_saved = import_upload.entity.funds.last.capital_commitments.last
    FormType.extract_from_db(@last_saved) if @last_saved

    Fund.where(id: fund_ids).each do |fund|
      # Compute the percentages
      fund.capital_commitments.last&.compute_percentage
      fund.save
    end
  end
end
