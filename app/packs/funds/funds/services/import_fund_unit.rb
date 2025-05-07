class ImportFundUnit < ImportUtil
  STANDARD_HEADERS = ["Fund", "Folio No", "Call / Distribution Name", "Unit Type",	"Quantity",	"Price", "Reason", "Premium", "Issue Date", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(row_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug row_data

    saved = true
    unit_type = row_data["Unit Type"]
    folio_id = row_data["Folio No"]&.to_s
    name = row_data["Call / Distribution Name"]
    update_only = row_data["Update Only"]
    quantity = row_data["Quantity"].to_d

    fund = import_upload.entity.funds.where(name: row_data["Fund"]).first
    raise "Fund not found" unless fund

    capital_commitment = fund.capital_commitments.where(folio_id:).first
    raise "Folio #{folio_id} not found in fund #{fund.name}" unless capital_commitment

    raise "Unit Type does not match commitment unit type" if capital_commitment.unit_type != unit_type

    owner = get_owner(fund, capital_commitment, name, quantity, folio_id)
    fund_unit = FundUnit.where(owner:).first

    if update_only == "Yes"
      if fund_unit.present?
        # Update only, and we have a pre-existing fund_unit
        save_fu(fund_unit, fund, capital_commitment, owner, row_data, custom_field_headers)
      else
        # Update only, but we dont have a pre-existing fund_unit
        raise "Skipping: FundUnit not found for update"
      end
    elsif fund_unit.nil? || FundUnit.where(owner:).where(issue_date: Date.parse(row_data["Issue Date"])).blank?
      fund_unit = FundUnit.new(entity_id: import_upload.entity_id, import_upload_id: import_upload.id)
      save_fu(fund_unit, fund, capital_commitment, owner, row_data, custom_field_headers)
      # No update, and we dont have a pre-existing fund_unit or the issue date of the fund unit is different
    else
      # No update, but we have a pre-existing fund_unit with the same issue date
      raise "Skipping: FundUnit already exists"
    end

    saved
  end

  # Depending on the quantity, we need to get the owner from either the capital_remittance or capital_distribution_payment
  def get_owner(fund, capital_commitment, name, quantity, folio_id)
    owner = nil

    if quantity.positive?
      capital_call = fund.capital_calls.where(name:).first
      raise "Call #{name} not found in fund #{fund.name}" unless capital_call

      capital_remittance = capital_commitment.capital_remittances.where(capital_call_id: capital_call.id).first
      raise "Remittance not found for #{folio_id} in call #{name} in fund #{fund.name}" unless capital_remittance

      owner = capital_remittance
    else
      capital_distribution = fund.capital_distributions.where(title: name).first
      raise "Distribution #{name} not found in fund #{fund.name}" unless capital_distribution

      capital_distribution_payment = capital_commitment.capital_distribution_payments.where(capital_distribution_id: capital_distribution.id).first
      raise "Distribution Payment not found for #{folio_id} in Distribution #{name} in fund #{fund.name}" unless capital_distribution

      owner = capital_distribution_payment
    end

    owner
  end

  def save_fu(fund_unit, fund, capital_commitment, owner, row_data, custom_field_headers)
    unit_type = row_data["Unit Type"]
    row_data["Folio No"]&.to_s

    fund_unit.assign_attributes(fund:, capital_commitment:, owner:, investor_id: capital_commitment.investor_id, unit_type:, quantity: row_data["Quantity"], price: row_data["Price"], reason: row_data["Reason"], premium: row_data["Premium"], issue_date: row_data["Issue Date"])

    setup_custom_fields(row_data, fund_unit, custom_field_headers)

    fund_unit.save!
  end
end
