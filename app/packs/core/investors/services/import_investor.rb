class ImportInvestor < ImportUtil
  include Interactor

  STANDARD_HEADERS = %w[Name PAN Category Tags City].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(import_upload, _context)
    import_upload.entity.investor_notices.each do |notice|
      InvestorNoticeJob.perform_now(notice.id)
    end
  end

  def save_investor(user_data, import_upload, custom_field_headers)
    # puts "processing #{user_data}"
    saved = true
    investor_name = user_data['Name'].strip
    pan = user_data['PAN'].strip
    category = user_data['Category'].strip.presence

    force_different_name = user_data['Force Different Name'] == "Yes"
    # Ensure Force Different Name is not part of custom fields
    custom_field_headers -= ["Force Different Name"]

    investor = Investor.where(investor_name:, pan:, entity_id: import_upload.entity_id).first
    if investor.present?
      Rails.logger.debug { "Investor with name investor_name already exists for entity #{import_upload.entity_id}" }

      raise "Investor with already exists." if user_data["Fund"].blank?
    else

      Rails.logger.debug user_data
      investor = Investor.new(investor_name:, pan:, tag_list: user_data["Tags"],
                              category:, city: user_data["City"],
                              entity_id: import_upload.entity_id, imported: true, force_different_name:)

      custom_field_headers.delete("Fund")

      setup_custom_fields(user_data, investor, custom_field_headers)

      Rails.logger.debug { "Saving Investor with name '#{investor.investor_name}'" }
      saved = investor.save!

    end

    add_to_fund(user_data, import_upload, investor)
    saved
  end

  def add_to_fund(user_data, import_upload, investor)
    Rails.logger.debug { "######## add_to_fund #{user_data['Fund']} #{import_upload.owner}" }
    # If fund name is present, add this investor to the fund
    if user_data["Fund"].present? || import_upload.owner_type == "Fund"
      if user_data["Fund"].present?
        Rails.logger.debug { "######## Fund present in import row #{user_data['Fund']}" }
        fund = Fund.where(entity_id: import_upload.entity_id, name: user_data["Fund"].strip).first
      elsif import_upload.owner_type == "Fund"
        fund = import_upload.owner
        Rails.logger.debug { "######## Fund present in import upload record #{fund.name}" }
      end

      if fund
        # Give the investor access rights as an investor to the fund
        AccessRight.create(entity_id: fund.entity_id, owner: fund, investor:, access_type: "Fund", metadata: "Investor")
      else
        Rails.logger.debug { "Specified fund #{user_data['Fund']} not found in import_upload #{import_upload.id}" }
      end
    end
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
    # create hash from headers and cells

    user_data = [headers, row].transpose.to_h
    Rails.logger.debug { "#### user_data = #{user_data}" }
    begin
      if save_investor(user_data, import_upload, custom_field_headers)
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
      Rails.logger.debug user_data
      Rails.logger.debug row
      import_upload.failed_row_count += 1
    end
  end
end
