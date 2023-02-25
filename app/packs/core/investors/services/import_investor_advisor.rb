class ImportInvestorAdvisor < ImportUtil
  include Interactor

  STANDARD_HEADERS = %w[Email Fund].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(import_upload, _context); end

  def save_investor_advisor(user_data, import_upload, _custom_field_headers)
    # puts "processing #{user_data}"
    saved = true
    email = user_data['Email'].strip
    investor_name = user_data['Investor'].strip
    entity = import_upload.entity
    investor = entity.investors.where(investor_name:).first

    investor_advisor = InvestorAdvisor.where(email:, entity_id: import_upload.entity_id).first
    if investor_advisor.present?
      Rails.logger.debug { "investor_advisor with email already exists for entity #{import_upload.entity_id}" }
    else
      Rails.logger.debug user_data
      investor_advisor = InvestorAdvisor.new(email:, entity_id: investor.investor_entity_id)
      saved = investor_advisor.save!
    end

    add_to_fund(user_data, import_upload, investor_advisor, investor)
    saved
  end

  def add_to_fund(user_data, import_upload, investor_advisor, investor)
    Rails.logger.debug { "######## add_to_fund #{user_data['Fund']} #{import_upload.owner}" }
    # If fund name is present, add this investor_advisor to the fund
    if user_data["Fund"].present? || import_upload.owner_type == "Fund"
      if user_data["Fund"].present?
        Rails.logger.debug { "######## Fund present in import row #{user_data['Fund']}" }
        fund = Fund.where(entity_id: import_upload.entity_id, name: user_data["Fund"].strip).first
      elsif import_upload.owner_type == "Fund"
        fund = import_upload.owner
        Rails.logger.debug { "######## Fund present in import upload record #{fund.name}" }
      end

      if fund
        # Give the investor_advisor access rights as an investor_advisor to the fund
        AccessRight.create(entity_id: investor_advisor.entity_id, owner: fund, user_id: investor_advisor.user_id, access_type: "Fund", metadata: "investor_advisor")

        # Give this user investor access in the investor
        user = investor_advisor.user
        investor.investor_accesses.create(email: user.email, first_name: user.first_name, last_name: user.last_name, approved: true, send_confirmation: false, entity_id:
        import_upload.entity_id, granted_by: import_upload.user_id)
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
      if save_investor_advisor(user_data, import_upload, custom_field_headers)
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
