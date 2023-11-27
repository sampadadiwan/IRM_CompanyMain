class ImportAccountEntry < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Folio No", "Reporting Date", "Entry Type", "Name", "Amount", "Notes", "Type"].freeze
  attr_accessor :account_entries

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(params)
    super(params)
    @account_entries = []
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      status, msg = save_account_entry(user_data, import_upload, custom_field_headers)
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

  def save_account_entry(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing account_entry #{user_data}" }

    folio_id, name, entry_type, reporting_date, investor_name, amount_cents, fund, capital_commitment, investor = get_fields(user_data, import_upload)
    # Get the Fund

    if fund && ((investor_name && capital_commitment) || investor_name.blank?)
      ret_val = prepare_record(user_data, import_upload, custom_field_headers)
    else
      ret_val = [false, "Fund not found"] if fund.nil?
      ret_val = [false, "Commitment not found"] if capital_commitment.nil?
    end

    ret_val
  end

  def prepare_record(user_data, import_upload, custom_field_headers)
    folio_id, name, entry_type, reporting_date, period, investor_name, amount_cents, fund, capital_commitment, investor = get_fields(user_data, import_upload)

    if fund

      # Note this could be an entry for a commitment or for a fund (i.e no commitment)
      account_entry = AccountEntry.find_or_initialize_by(entity_id: import_upload.entity_id, folio_id:,
                                                         fund:, capital_commitment:, investor:, reporting_date:,
                                                         entry_type:, name:, amount_cents:)

      if account_entry.new_record? && account_entry.valid?
        account_entry.notes = user_data["Notes"]
        account_entry.commitment_type = user_data["Type"]
        setup_custom_fields(user_data, account_entry, custom_field_headers)

        account_entry.run_callbacks(:save) { false }
        account_entry.run_callbacks(:create) { false }
        @account_entries << account_entry
        ret_val = if account_entry.valid?
                    [true, "Success"]
                  else
                    [false, account_entry.errors.full_messages]
                  end
      else
        ret_val = [false, "Duplicate, already present"] unless account_entry.new_record?
        ret_val = [false, account_entry.errors.full_messages] unless account_entry.valid?
      end
    else
      raise "Fund not found" unless fund
    end

    ret_val
  end

  def get_fields(user_data, import_upload)
    folio_id = user_data["Folio No"]&.to_s&.strip
    name = user_data["Name"].presence
    entry_type = user_data["Entry Type"].presence
    reporting_date = user_data["Reporting Date"].presence
    investor_name = user_data["Investor"]&.strip&.squeeze(" ")
    amount_cents = user_data["Amount"].to_d * 100
    period = user_data["Period"]&.strip&.squeeze(" ")

    fund = import_upload.entity.funds.where(name: user_data["Fund"].strip).first
    raise "Fund not found" unless fund

    capital_commitment = investor_name.present? ? fund.capital_commitments.where(investor_name:, folio_id:).first : nil
    investor = capital_commitment&.investor
    raise "Commitment not found" if folio_id.present? && capital_commitment.nil?

    [folio_id, name, entry_type, reporting_date, period, investor_name, amount_cents, fund, capital_commitment, investor]
  end

  def post_process(import_upload, context)
    # Import it

    begin
      results = AccountEntry.import @account_entries, on_duplicate_key_ignore: true, validate_uniqueness: true, track_validation_failures: true
    rescue StandardError => e
      import_upload.status = "Failed to import all rows #{e.message}"
      import_upload.error_text = "Failed to import #{e.backtrace}"
      import_upload.save
    end

    # Check for failures - this is bug in the gem, its not returning the errors

    # Sometimes we import custom fields. Ensure custom fields get created
    custom_field_headers = context.headers - standard_headers
    FormType.save_cf_from_import(custom_field_headers, import_upload) if import_upload.processed_row_count.positive?
  end
end
