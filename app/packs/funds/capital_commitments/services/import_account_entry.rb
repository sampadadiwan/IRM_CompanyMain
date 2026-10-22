class ImportAccountEntry < ImportUtil
  STANDARD_HEADERS = ["Fund", "Folio No", "Reporting Date", "Entry Type", "Name", "Amount (Folio Currency)", "Amount (Fund Currency)", "Notes", "Rule For", "Parent Type", "Parent Id"].freeze
  attr_accessor :account_entries

  def standard_headers
    STANDARD_HEADERS
  end

  # Older templates may still carry an Investor column - ignore it so it does not become a custom field
  def ignore_headers
    ["Investor"]
  end

  def initialize(**)
    super
    @account_entries = []
    @funds = Set.new
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing account_entry #{user_data}" }

    # Get the Fund
    fields = get_fields(user_data, import_upload)
    folio_id, name, entry_type, reporting_date, period, investor_name, folio_amount_cents, fund_amount_cents, fund, capital_commitment, investor = fields

    # The entry is commitment level if a folio is given, else fund level
    if fund && (folio_id.blank? || capital_commitment)
      # ret_val = prepare_record(user_data, import_upload, custom_field_headers)
      # Pass the fields along so the fund / commitment / investor lookups aren't run a second time for this row
      save_account_entry(user_data, import_upload, custom_field_headers, fields)
    else
      raise "Fund not found: #{user_data['Fund']}" if fund.nil?
      raise "Capital Commitment not found in fund #{fund.name} for folio #{folio_id}" if capital_commitment.nil?
    end
  end

  # fields: get_fields' result when the caller already has it; looked up here otherwise
  def save_account_entry(user_data, import_upload, custom_field_headers, fields = get_fields(user_data, import_upload))
    folio_id, name, entry_type, reporting_date, period, investor_name, folio_amount_cents, fund_amount_cents, fund, capital_commitment, investor, rule_for, parent_type, parent_id, ref_id, cumulative = fields

    if fund

      # Note this could be an entry for a commitment or for a fund (i.e no commitment)
      account_entry = AccountEntry.find_or_initialize_by(entity_id: import_upload.entity_id, folio_id:, fund:, capital_commitment:, investor:, reporting_date:, entry_type:, rule_for:, name:, amount_cents: fund_amount_cents, folio_amount_cents:, parent_type:, parent_id:, ref_id:, cumulative:)

      if account_entry.new_record? && account_entry.valid?

        validate_parent_presence(account_entry)
        account_entry.notes = user_data["Notes"]
        account_entry.import_upload_id = import_upload.id

        custom_field_headers.delete("Ref Id")
        custom_field_headers.delete("Cumulative")
        setup_custom_fields(user_data, account_entry, custom_field_headers)

        account_entry.save!
      else
        msg = "Duplicate account entry - #{entry_type} '#{name}' already exists for fund #{fund.name}#{", folio #{folio_id}" if folio_id.present?} on #{reporting_date}"
        Rails.logger.debug { "#{msg} #{account_entry}" }
        raise msg unless account_entry.new_record?
        raise account_entry.errors.full_messages.join(",") unless account_entry.valid?
      end
    else
      raise "Fund not found: #{user_data['Fund']}"
    end
  end

  def get_fields(user_data, import_upload)
    folio_id = user_data["Folio No"]&.to_s
    name = user_data["Name"].presence
    entry_type = user_data["Entry Type"].presence
    reporting_date = parse_date_cell(user_data, "Reporting Date")
    folio_amount_cents = user_data["Amount (Folio Currency)"].to_d * 100
    fund_amount_cents = user_data["Amount (Fund Currency)"].to_d * 100
    period = user_data["Period"]
    rule_for = user_data["Rule For"]&.downcase
    parent_type = user_data["Parent Type"]
    parent_id = user_data["Parent Id"]
    ref_id = user_data["Ref Id"].to_i
    cumulative = user_data["Cumulative"] == "true"

    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first
    raise "Fund not found: #{user_data['Fund']}" unless fund

    @funds.add(fund)

    # Map the row to the commitment purely via the folio id - the investor is derived from the commitment.
    # Note this could be an entry for a commitment (folio given) or for a fund (no folio)
    capital_commitment = folio_id.present? ? fund.capital_commitments.where(folio_id:).first : nil
    investor = capital_commitment&.investor
    investor_name = capital_commitment&.investor_name
    raise "Capital Commitment not found in fund #{fund.name} for folio #{folio_id}" if folio_id.present? && capital_commitment.nil?

    [folio_id, name, entry_type, reporting_date, period, investor_name, folio_amount_cents, fund_amount_cents, fund, capital_commitment, investor, rule_for, parent_type, parent_id, ref_id, cumulative]
  end

  def validate_parent_presence(account_entry)
    parent_type = account_entry.parent_type.to_s

    if account_entry.parent_type.present? && account_entry.parent_id.blank?
      raise "Parent Id must be specified when Parent Type is #{parent_type}"
    elsif account_entry.parent_id.present? && account_entry.parent_type.blank?
      raise "Parent Type must be specified when Parent Id is #{account_entry.parent_id}"
    elsif account_entry.parent_type.present? && account_entry.parent_id.present?
      # Parent Type is free text from the sheet. Reading the polymorphic association
      # with an unknown type raises "uninitialized constant Foo", which says nothing
      # about the column at fault - so resolve the name first without blowing up.
      parent_class = parent_type.safe_constantize
      raise "Parent Type '#{parent_type}' is not a valid record type" unless parent_class.respond_to?(:find_by)

      raise "Parent #{parent_type} #{account_entry.parent_id} not found" if account_entry.parent.nil?

      if parent_type != "Investor"
        ae_fund_id = account_entry.fund_id
        parent_fund_id = account_entry.parent.fund_id

        if (parent_fund_id != ae_fund_id) && (account_entry.fund.master_fund_id != parent_fund_id)
          # ae and parent should be in the same fund or parent's fund should be the master fund of ae's fund
          raise "Parent #{parent_type} #{account_entry.parent_id} belongs to fund id #{parent_fund_id}, not to #{account_entry.fund.name}"
        end
      end
    end
  end

  def post_process(_ctx, import_upload:, **)
    super
    # For each fund, resave the portfolio investments to ensure they are up to date with the latest expense entries
    @funds.each do |fund|
      Rails.logger.debug { "Resaving portfolio investments for fund #{fund.name}" }
      fund.resave_portfolio_investments
    end
    true
  end
end
