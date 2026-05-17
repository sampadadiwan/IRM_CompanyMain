class ImportDealInvestor < ImportUtil
  STANDARD_HEADERS = ["Investor Name", "Status", "Tier", "Primary Amount (USD)", "Secondary Amount (USD)",
                       "Pre Money Valuation (USD)", "Deal Lead", "Source", "Tags",
                       "Company Advisor", "Investor Advisor", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    raise "Import owner must be a Deal" unless import_upload.owner_type == "Deal"

    deal = import_upload.owner
    entity_id = import_upload.entity_id

    investor_name = user_data["Investor Name"].to_s.strip
    raise "Investor Name is required" if investor_name.blank?

    investor = Investor.where(investor_name:, entity_id:).first
    raise "Investor '#{investor_name}' not found. Please add them first before importing." if investor.nil?

    update_only = user_data["Update Only"]
    deal_investor = DealInvestor.where(deal_id: deal.id, investor_id: investor.id).first

    # Update Only
    # 1. DealInvestor found - update
    # 2. DealInvestor not found - raise (skip)
    # No Update Only flag
    # 3. DealInvestor not found - create new
    # 4. DealInvestor found - raise (skip duplicate)
    if update_only == "Yes"
      raise "Skipping: DealInvestor not found for update" if deal_investor.nil?
    elsif deal_investor.present?
      raise "Skipping: DealInvestor for investor already exists"
    else
      deal_investor = DealInvestor.new(deal_id: deal.id, investor_id: investor.id)
    end

    primary_cents   = parse_money(user_data["Primary Amount (Usd)"])
    secondary_cents = parse_money(user_data["Secondary Amount (Usd)"])
    pre_money_cents = parse_money(user_data["Pre Money Valuation (Usd)"])

    deal_investor.assign_attributes(
      entity_id:,
      status:              user_data["Status"].presence&.strip || DealInvestor::STATUS.first,
      tier:                user_data["Tier"].presence&.strip,
      deal_lead:           user_data["Deal Lead"].presence&.strip,
      source:              user_data["Source"].presence&.strip,
      tags:                user_data["Tags"].presence&.strip,
      company_advisor:     user_data["Company Advisor"].presence&.strip,
      investor_advisor:    user_data["Investor Advisor"].presence&.strip,
      primary_amount_cents:        primary_cents,
      secondary_investment_cents:  secondary_cents,
      pre_money_valuation_cents:   pre_money_cents,
      import_upload_id:    import_upload.id
    )
    deal_investor.save!

    # Create deal activities from the deal's own templates with default (Incomplete) status
    # Only for new deal investors — existing ones already have their activities
    if deal_investor.previously_new_record?
      templates = DealActivity.templates(deal)
      templates.each do |template|
        activity = DealActivity.where(deal_id: deal.id, deal_investor_id: deal_investor.id,
                                      template_id: template.id).first_or_initialize
        next unless activity.new_record?

        activity.assign_attributes(
          entity_id:,
          title:       template.title,
          status:      "incomplete",
          days:        template.days || 0,
          sequence:    template.sequence,
          template_id: template.id
        )
        activity.save!
      end

      # Set current deal_activity pointer to the first incomplete step
      first_step = deal_investor.deal_activities.order(:sequence).first
      deal_investor.update_column(:deal_activity_id, first_step.template_id) if first_step&.template_id
    end

    true
  end

  private

  def parse_money(value)
    return 0 if value.blank?

    value.to_s.gsub(/[^0-9.]/, "").to_d * 100
  end
end
