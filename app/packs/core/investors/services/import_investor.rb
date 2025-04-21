class ImportInvestor < ImportUtil
  STANDARD_HEADERS = ["Name", "Pan", "Primary Email", "Category", "Tags", "City"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(ctx, import_upload:, **)
    super
    import_upload.entity.investor_notices.each do |notice|
      InvestorNoticeJob.perform_now(notice.id)
    end
    true
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    investor_name, pan, primary_email, category, update_only, force_different_name = get_data(user_data, custom_field_headers)

    investor = pan.present? ? Investor.where(investor_name:, pan:, entity_id: import_upload.entity_id).first : nil
    investor ||= Investor.where(investor_name:, primary_email:, entity_id: import_upload.entity_id).first

    if update_only
      if investor.blank?
        Rails.logger.debug { "Investor #{investor_name} not found for entity #{import_upload.entity_id}" }
        raise "Investor #{investor_name} not found for entity #{import_upload.entity_id}"
      else
        # Update the existing investor
        investor.assign_attributes(pan:, tag_list: user_data["Tags"],
                                   category:, city: user_data["City"], primary_email:,
                                   import_upload_id: import_upload.id,
                                   entity_id: import_upload.entity_id, imported: true, force_different_name:)
      end
    elsif investor.present?
      Rails.logger.debug { "Investor #{investor_name} already exists for entity #{import_upload.entity_id}" }
      raise "Investor #{investor_name} already exists."
    else
      # Create a new investor
      Rails.logger.debug user_data
      investor = Investor.new(investor_name:, pan:, tag_list: user_data["Tags"],
                              category:, city: user_data["City"], primary_email:,
                              import_upload_id: import_upload.id,
                              entity_id: import_upload.entity_id, imported: true, force_different_name:)
    end

    # Set the custom fields
    custom_field_headers.delete("Fund")
    setup_custom_fields(user_data, investor, custom_field_headers)
    # Save the investor
    Rails.logger.debug { "Saving Investor with name '#{investor.investor_name}'" }
    saved = investor.save!
    # Add the investor to the fund if a fund name is present
    add_to_fund(user_data, import_upload, investor)
    saved
  end

  def get_data(user_data, _custom_field_headers)
    # puts "processing #{user_data}"
    investor_name = user_data['Name']
    pan = user_data['Pan']
    primary_email = user_data['Primary Email']
    category = user_data['Category']
    update_only = user_data['Update Only'] == "Yes"
    # Ensure Update Only is not part of custom fields
    force_different_name = user_data['Force Different Name'] == "Yes"
    # Ensure Force Different Name is not part of custom fields

    [investor_name, pan, primary_email, category, update_only, force_different_name]
  end

  def add_to_fund(user_data, import_upload, investor)
    Rails.logger.debug { "######## add_to_fund #{user_data['Fund']} #{import_upload.owner}" }
    # If fund name is present, add this investor to the fund
    if user_data["Fund"].present? || import_upload.owner_type == "Fund"
      if user_data["Fund"].present?
        Rails.logger.debug { "######## Fund present in import row #{user_data['Fund']}" }
        fund = Fund.where(entity_id: import_upload.entity_id, name: user_data["Fund"]).first
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
end
