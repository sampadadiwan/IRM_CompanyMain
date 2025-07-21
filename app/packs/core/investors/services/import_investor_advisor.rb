class ImportInvestorAdvisor < ImportUtil
  STANDARD_HEADERS = ["Email", "Add To", "Name", "Investor", "Allowed Roles"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    # puts "processing #{user_data}"
    saved = true
    email = user_data['Email']
    investor_name = user_data['Investor']
    allowed_roles = user_data['Allowed Roles'].present? ? user_data['Allowed Roles'].downcase.split(',').map(&:strip) : %w[employee investor]

    entity = import_upload.entity
    investor = entity.investors.where(investor_name:).first
    pre_process_investor_account(user_data)

    investor_advisor = InvestorAdvisor.where(email:, entity_id: investor.investor_entity_id).first

    if investor_advisor.present?
      Rails.logger.debug { "investor_advisor with email already exists for entity #{investor.investor_entity_id}" }
    else
      Rails.logger.debug user_data
      investor_advisor = InvestorAdvisor.new(email:, entity_id: investor.investor_entity_id, created_by_id:
                            import_upload.user_id, import_upload_id: import_upload.id, allowed_roles:, permissions: investor.investor_entity.permissions, extended_permissions: %i[investor_kyc_read investor_read], owner_name: user_data['Name'])

      saved = investor_advisor.save!
    end

    add_to_owner(user_data, import_upload, investor_advisor, investor)
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

    user.add_role(:investor_advisor)
  end

  def add_to_owner(user_data, import_upload, investor_advisor, investor)
    Rails.logger.debug { "######## add_to_owner #{user_data['Name']} #{import_upload.owner}" }

    if user_data["Add To"].present? && user_data["Name"].present?
      if user_data["Add To"] == "Fund"
        # If fund name is present, add this investor_advisor to the fund
        Rails.logger.debug { "######## Fund present in import row #{user_data['Name']}" }
        owner = Fund.where(entity_id: import_upload.entity_id, name: user_data["Name"]).first
      elsif user_data["Add To"] == "Secondary Sale"
        # If secondary sale name is present, add this investor_advisor to the secondary sale
        Rails.logger.debug { "######## Secondary Sale present in import row #{user_data['Name']}" }
        owner = SecondarySale.where(entity_id: import_upload.entity_id, name: user_data["Name"]).first
      else
        # If Add To is not recognized, raise an error
        Rails.logger.debug { "######## Add To not recognized in import row #{user_data['Name']}" }
        raise "Add To not recognized"
      end

      if owner
        # Give the investor_advisor access rights as an investor_advisor to the Fund or SecondarySale
        ar = AccessRight.create(entity_id: investor_advisor.entity_id, owner:, user_id: investor_advisor.user_id, access_type: owner.class.name, metadata: "investor_advisor")

        Rails.logger.debug { "Error saving AccessRight: #{ar.errors}" } if ar.errors.present?

        # Give this user investor access in the investor
        user = investor_advisor.user
        investor.investor_accesses.create!(email: user.email, first_name: user.first_name, last_name: user.last_name, email_enabled: true, approved: true, send_confirmation: false, entity_id: import_upload.entity_id, granted_by: import_upload.user_id) if investor.investor_accesses.where(email: user.email, entity_id: import_upload.entity_id).blank?

      else
        Rails.logger.debug { "Specified #{user_data['Add To']} #{user_data['Name']} not found" }
        raise "#{user_data['Add To']} #{user_data['Name']} not found"
      end
    end
  end
end
