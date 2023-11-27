class ImportFundUnitSetting < ImportUtil
  include Interactor

  STANDARD_HEADERS = ["Fund", "Class/Series", "Management Fee %",	"Setup Fee %",	"Carry %", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_fund_unit_setting(row_data, import_upload, custom_field_headers)
    Rails.logger.debug row_data

    saved = true
    name = row_data["Class/Series"]&.strip&.squeeze(" ")
    update_only = row_data["Update Only"]&.strip&.squeeze(" ")

    fund = import_upload.entity.funds.where(name: row_data["Fund"].strip).first
    raise "Fund not found" unless fund

    fund_unit_setting = FundUnitSetting.where(fund_id: fund.id,
                                              entity_id: import_upload.entity_id, name:).first

    if fund_unit_setting.present? && update_only == "Yes"
      save_fus(fund_unit_setting, fund, row_data, custom_field_headers)

    elsif fund_unit_setting.nil?
      fund_unit_setting = FundUnitSetting.new(entity_id: import_upload.entity_id)
      save_fus(fund_unit_setting, fund, row_data, custom_field_headers)

    else
      raise "Skipping: FundUnitSetting for fund already exists"
    end

    saved
  end

  def save_fus(fund_unit_setting, fund, row_data, custom_field_headers)
    fund_unit_setting.assign_attributes(fund:,
                                        name: row_data["Class/Series"]&.strip&.squeeze(" "),
                                        management_fee: row_data["Management Fee %"].to_s&.strip,
                                        setup_fee: row_data["Setup Fee %"]&.to_s&.strip,
                                        carry: row_data["Carry %"].to_s&.strip)

    setup_custom_fields(row_data, fund_unit_setting, custom_field_headers)

    fund_unit_setting.save!
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
    # create hash from headers and cells

    row_data = [headers, row].transpose.to_h

    Rails.logger.debug { "#### row_data = #{row_data}" }
    begin
      if save_fund_unit_setting(row_data, import_upload, custom_field_headers)
        import_upload.processed_row_count += 1
        row << "Success"
      else
        import_upload.failed_row_count += 1
        row << "Error"
      end
    rescue ActiveRecord::Deadlocked => e
      raise e
    rescue StandardError => e
      Rails.logger.debug e.message
      row << "Error #{e.message}"
      Rails.logger.debug row_data
      Rails.logger.debug row
      import_upload.failed_row_count += 1
    end
  end
end
