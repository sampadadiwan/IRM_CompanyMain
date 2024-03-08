class ImportInvestorAdvisor < ImportUtil
  include Interactor

  STANDARD_HEADERS = ["Email", "Add To", "Name", "Investor"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(import_upload, _context); end

  def save_row(user_data, import_upload, _custom_field_headers)
    # puts "processing #{user_data}"
    saved = true
    email = user_data['Email']
    investor_name = user_data['Investor']
    entity = import_upload.entity
    investor = entity.investors.where(investor_name:).first

    investor_advisor = InvestorAdvisor.where(email:, entity_id: investor.investor_entity_id).first
    if investor_advisor.present?
      Rails.logger.debug { "investor_advisor with email already exists for entity #{investor.investor_entity_id}" }
    else
      Rails.logger.debug user_data
      investor_advisor = InvestorAdvisor.new(email:, entity_id: investor.investor_entity_id,
                                             import_upload_id: import_upload.id,
                                             allowed_roles: %i[employee investor],
                                             permissions: investor.investor_entity.permissions, extended_permissions: %i[investor_kyc_read investor_read])
      saved = investor_advisor.save!
    end

    add_to_fund(user_data, import_upload, investor_advisor, investor)
    saved
  end

  def add_to_fund(user_data, import_upload, investor_advisor, investor)
    Rails.logger.debug { "######## add_to_fund #{user_data['Name']} #{import_upload.owner}" }
    # If fund name is present, add this investor_advisor to the fund
    if user_data["Add To"].present? && user_data["Name"].present?
      if user_data["Add To"] == "Fund"
        Rails.logger.debug { "######## Fund present in import row #{user_data['Name']}" }
        fund = Fund.where(entity_id: import_upload.entity_id, name: user_data["Name"]).first
      end

      if fund
        # Give the investor_advisor access rights as an investor_advisor to the fund
        ar = AccessRight.create(entity_id: investor_advisor.entity_id, owner: fund, user_id: investor_advisor.user_id, access_type: "Fund", metadata: "investor_advisor")

        Rails.logger.debug { "Error saving AccessRight: #{ar.errors}" } if ar.errors.present?

        # Give this user investor access in the investor
        user = investor_advisor.user
        investor.investor_accesses.where(email: user.email, entity_id: import_upload.entity_id).find_each(&:destroy)
        investor.investor_accesses.create!(email: user.email, first_name: user.first_name, last_name: user.last_name, approved: true, send_confirmation: false, entity_id: import_upload.entity_id, granted_by: import_upload.user_id)

      else
        Rails.logger.debug { "Specified fund #{user_data['Fund']} not found in import_upload #{import_upload.id}" }
        raise "Fund not found #{user_data['Name']}"
      end
    end
  end
end
