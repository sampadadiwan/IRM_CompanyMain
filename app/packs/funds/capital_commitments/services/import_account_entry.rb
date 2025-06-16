class ImportAccountEntry < ImportUtil
  STANDARD_HEADERS = ["Investor", "Fund", "Folio No", "Reporting Date", "Entry Type", "Name", "Amount (Folio Currency)", "Amount (Fund Currency)", "Notes", "Rule For", "Parent Type", "Parent Id"].freeze
  attr_accessor :account_entries

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(**)
    super
    @account_entries = []
    @funds = Set.new
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug { "Processing account_entry #{user_data}" }

    # Get the Fund
    folio_id, name, entry_type, reporting_date, period, investor_name, folio_amount_cents, fund_amount_cents, fund, capital_commitment, investor = get_fields(user_data, import_upload)

    if fund && ((investor_name && capital_commitment) || investor_name.blank?)
      # ret_val = prepare_record(user_data, import_upload, custom_field_headers)
      save_account_entry(user_data, import_upload, custom_field_headers)
    else
      raise "Fund not found" if fund.nil?
      raise "Commitment not found" if capital_commitment.nil?
    end
  end

  def save_account_entry(user_data, import_upload, custom_field_headers)
    folio_id, name, entry_type, reporting_date, period, investor_name, folio_amount_cents, fund_amount_cents, fund, capital_commitment, investor, rule_for, parent_type, parent_id, ref_id, cumulative = get_fields(user_data, import_upload)

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
        msg = "Duplicate, already present"
        Rails.logger.debug { "#{msg} #{account_entry}" }
        raise msg unless account_entry.new_record?
        raise account_entry.errors.full_messages.join(",") unless account_entry.valid?
      end
    else
      raise "Fund not found" unless fund
    end
  end

  def get_fields(user_data, import_upload)
    folio_id = user_data["Folio No"]&.to_s
    name = user_data["Name"].presence
    entry_type = user_data["Entry Type"].presence
    reporting_date = user_data["Reporting Date"].presence
    investor_name = user_data["Investor"]
    folio_amount_cents = user_data["Amount (Folio Currency)"].to_d * 100
    fund_amount_cents = user_data["Amount (Fund Currency)"].to_d * 100
    period = user_data["Period"]
    rule_for = user_data["Rule For"]&.downcase
    parent_type = user_data["Parent Type"]
    parent_id = user_data["Parent Id"]
    ref_id = user_data["Ref Id"].to_i
    cumulative = user_data["Cumulative"] == "true"

    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first
    raise "Fund not found" unless fund

    @funds.add(fund)

    capital_commitment = investor_name.present? ? fund.capital_commitments.where(investor_name:, folio_id:).first : nil
    investor = capital_commitment&.investor
    raise "Commitment not found" if folio_id.present? && capital_commitment.nil?

    [folio_id, name, entry_type, reporting_date, period, investor_name, folio_amount_cents, fund_amount_cents, fund, capital_commitment, investor, rule_for, parent_type, parent_id, ref_id, cumulative]
  end

  def validate_parent_presence(account_entry)
    if account_entry.parent_type.present? && account_entry.parent_id.blank?
      raise "Parent Id not present"
    elsif account_entry.parent_id.present? && account_entry.parent_type.blank?
      raise "Parent Type not present"
    elsif account_entry.parent_type.present? && account_entry.parent_id.present?
      raise "Parent not found" if account_entry.parent.nil?
      raise "Parent does not belong to Fund" if account_entry.parent_type.to_s != "Investor" && account_entry.parent.fund_id != account_entry.fund_id
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
