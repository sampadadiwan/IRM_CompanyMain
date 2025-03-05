class ImportFundUnitSetting < ImportUtil
  STANDARD_HEADERS = ["Fund", "Class/Series", "Management Fee %",	"Setup Fee %",	"Carry %", "Gp Units", "Update Only", "Isin"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(row_data, import_upload, custom_field_headers, _ctx)
    Rails.logger.debug row_data

    saved = true
    name = row_data["Class/Series"]
    update_only = row_data["Update Only"]

    fund = import_upload.entity.funds.where(name: row_data["Fund"]).first
    raise "Fund not found" unless fund

    fund_unit_setting = FundUnitSetting.where(fund_id: fund.id,
                                              entity_id: import_upload.entity_id, name:).first

    if update_only == "Yes"
      if fund_unit_setting.present?
        # Update only, and we have a pre-existing fund_unit_setting
        saved = save_fus(fund_unit_setting, fund, row_data, custom_field_headers, import_upload)
      else
        # Update only, but we dont have a pre-existing fund_unit_setting
        raise "Skipping: FundUnitSetting not found for update"
      end
    elsif fund_unit_setting.nil?
      fund_unit_setting = FundUnitSetting.new(entity_id: import_upload.entity_id, import_upload_id: import_upload.id)
      saved = save_fus(fund_unit_setting, fund, row_data, custom_field_headers, import_upload)
    # No update, and we dont have a pre-existing fund_unit_setting
    else
      # No update, but we have a pre-existing fund_unit_setting
      raise "Skipping: FundUnitSetting for fund already exists"
    end

    saved
  end

  def save_fus(fund_unit_setting, fund, row_data, custom_field_headers, import_upload)
    gp_units = row_data['Gp Units'].to_s.strip.casecmp?("Yes")
    fund_unit_setting.assign_attributes(fund:, import_upload_id: import_upload.id,
                                        name: row_data["Class/Series"],
                                        management_fee: row_data["Management Fee %"].to_s,
                                        setup_fee: row_data["Setup Fee %"]&.to_s,
                                        carry: row_data["Carry %"].to_s,
                                        gp_units: gp_units,
                                        isin: row_data["Isin"])

    setup_custom_fields(row_data, fund_unit_setting, custom_field_headers)

    fund_unit_setting.save!
  end
end
