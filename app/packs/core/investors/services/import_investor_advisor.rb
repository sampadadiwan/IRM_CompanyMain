class ImportInvestorAdvisor < ImportUtil
  STANDARD_HEADERS = ["Email", "Add To", "Name", "Investor"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, _custom_field_headers)
    # puts "processing #{user_data}"
    saved = true
    email = user_data['Email']
    investor_name = user_data['Investor']
    entity = import_upload.entity
    investor = entity.investors.where(investor_name:).first
    pre_process_investor_account(user_data)
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

  def pre_process_investor_account(user_data)
    user = User.find_by(email: user_data["Email"])
    return if user.present?

    entity = Entity.find_by(name: user_data["Advisor Entity"])
    entity = create_entity(user_data["Advisor Entity"], user_data["Email"]) if entity.nil?
    create_user(user_data, entity)
  end

  def create_entity(advisor_entity, primary_email)
    entity = Entity.new(name: advisor_entity, primary_email:, entity_type: "Investor Advisor")
    entity.save!
    entity
  end

  def create_user(user_data, entity)
    raise "First name not present" if user_data["First Name"].blank?
    raise "Last name not present" if user_data["Last Name"].blank?

    password = SecureRandom.alphanumeric
    user = User.new(first_name: user_data["First Name"], last_name: user_data["Last Name"],
                    email: user_data["Email"], entity_id: entity.id, password:)
    user.confirm
    user.save!
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
        investor.investor_accesses.create!(email: user.email, first_name: user.first_name, last_name: user.last_name, email_enabled: false, approved: true, send_confirmation: false, entity_id: import_upload.entity_id, granted_by: import_upload.user_id)
        notify_investor_team(investor, investor_advisor, import_upload, user_data['Name'])
      else
        Rails.logger.debug { "Specified fund #{user_data['Fund']} not found in import_upload #{import_upload.id}" }
        raise "Fund not found #{user_data['Name']}"
      end
    end
  end

  def notify_investor_team(investor, investor_advisor, import_upload, fund_name)
    investor.users.each do |user|
      InvestorAdvisorNotifier.with(entity_id: import_upload.entity_id, investor_advisor:, investor:, import_upload:, fund_name:, email_method: :notify_investor_advisor_addition, msg: "Investor Advisor #{investor_advisor.user.first_name} #{investor_advisor.user.last_name} with email #{investor_advisor.email} is added by #{import_upload.entity.name}").deliver_later(user)
    end
  end
end
