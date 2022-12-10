class ImportCapitalCommittment < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Committed Amount", "Notes", "Folio No"].freeze
  attr_accessor :commitments

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(params)
    super(params)
    @commitments = []
  end

  def process_row(headers, custom_field_headers, row, import_upload)
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
      row << "Error #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  def save_capital_commitment(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_commitment #{user_data}" }

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first
    folio_id = user_data["Folio No"].presence

    if fund && investor
      # Make the capital_commitment
      capital_commitment = CapitalCommitment.new(entity_id: import_upload.entity_id, folio_id:,
                                                 fund:, investor:, notes: user_data["Notes"])

      capital_commitment.committed_amount = user_data["Committed Amount"].to_d

      setup_custom_fields(user_data, capital_commitment, custom_field_headers)

      if capital_commitment.valid?
        @commitments << capital_commitment
        [true, "Success"]
      else
        [false, capital_commitment.errors.full_messages]
      end
    elsif fund
      [false, "Investor not found"]
    else
      [false, "Fund not found"]
    end
  end

  def post_process(import_upload)
    # Import it
    CapitalCommitment.import @commitments, on_duplicate_key_update: %i[folio_id notes committed_amount_cents]

    # Sometimes we import custom fields. Ensure custom fields get created
    @last_saved = import_upload.entity.funds.last.capital_commitments.last
    FormType.extract_from_db(@last_saved) if @last_saved

    import_upload.entity.funds.each do |fund|
      # Compute the percentages
      fund.capital_commitments.last&.compute_percentage
      # Ensure the counter caches are updated
      fund.committed_amount_cents = fund.capital_commitments.sum(:committed_amount_cents)
      fund.collected_amount_cents = fund.capital_commitments.sum(:collected_amount_cents)
      fund.save
    end
  end
end
