class ImportDealInvestor < ImportUtil
  # Standard columns recognised from the Deal Investors sheet.
  # Every column present in the upload that is NOT in this list is treated
  # as a custom field and stored in json_fields.
  STANDARD_FIELD_MAP = {
    "Deal Investor" => nil, # investor lookup — not a model attribute
    "Status" => :status,
    "Tags" => :tags,
    "Source" => :source,
    "Deal Lead" => :deal_lead,
    "Tier" => :tier,
    "Primary Amount" => :primary_amount_cents, # parsed to cents
    "Secondary Amount" => :secondary_investment_cents, # parsed to cents
    "Pre Money Valuation" => :pre_money_valuation_cents # parsed to cents, optional
  }.freeze

  # -----------------------------------------------------------------------
  # validate_headers — only "Deal Investor" is required
  # -----------------------------------------------------------------------
  def validate_headers(_ctx, deal_investors_sheet:, import_upload:, **)
    headers = deal_investors_sheet[:headers]
    return true if headers.include?("Deal Investor")

    import_upload.status           = "Column(s) not found: Deal Investor"
    import_upload.failed_row_count = [deal_investors_sheet[:data].length - 1, 0].max
    import_upload.save
    false
  end

  # -----------------------------------------------------------------------
  # save_data — process all three sheets
  # -----------------------------------------------------------------------
  def save_data(ctx, import_upload:, deal_investors_sheet:, deal_steps_sheet: nil, notes_sheet: nil, **)
    process_deal_investors(import_upload, deal_investors_sheet, ctx)
    process_deal_steps(import_upload, deal_steps_sheet)    if deal_steps_sheet
    process_notes(import_upload, notes_sheet)              if notes_sheet
    import_upload.save!
    true
  end

  private

  # -----------------------------------------------------------------------
  # Sheet 1 — Deal Investors
  # -----------------------------------------------------------------------
  def process_deal_investors(import_upload, sheet, ctx)
    deal      = import_upload.owner
    entity_id = import_upload.entity_id
    headers   = sheet[:headers]

    # Columns not in STANDARD_FIELD_MAP go to json_fields
    custom_headers = headers - STANDARD_FIELD_MAP.keys
    ctx[:custom_field_headers] = custom_headers

    # Build results xlsx so failures can be inspected by the user
    package = Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Deal Investors Results") do |ws|
        ws.add_row(headers + ["Result"])

        sheet[:data][1..].each_with_index do |row, i|
          sanitized = row[..(headers.length - 1)].map { |x| x&.to_s&.strip&.squeeze(" ") }
          user_data = headers.zip(sanitized).to_h

          Audited.audit_class.as_user(import_upload.user) do
            save_investor_row(user_data, import_upload, custom_headers, ctx, deal, entity_id, sanitized)
          end

          ws.add_row(sanitized)
          import_upload.save if ((i + 1) % 10).zero?
        end
      end
    end

    File.binwrite("/tmp/import_result_#{import_upload.id}.xlsx", package.to_stream.read)
  end

  def save_investor_row(user_data, import_upload, custom_headers, _ctx, deal, entity_id, result_row)
    investor_name = user_data["Deal Investor"].to_s.strip
    raise "Deal Investor name is required" if investor_name.blank?

    investor = Investor.where(investor_name:, entity_id:).first
    raise "Investor '#{investor_name}' not found. Please add them first." if investor.nil?

    # Raise for duplicates — this import format has no Update Only column
    deal_investor = DealInvestor.where(deal_id: deal.id, investor_id: investor.id).first
    if deal_investor
      raise "Skipping: DealInvestor for investor already exists"
    else
      deal_investor = DealInvestor.new(deal_id: deal.id, investor_id: investor.id)
    end

    primary_cents   = parse_money(user_data["Primary Amount"])
    secondary_cents = parse_money(user_data["Secondary Amount"])
    pre_money_cents = parse_money(user_data["Pre Money Valuation"]) # 0 when blank
    allowed_statuses = allowed_statuses_for(deal)
    status_value = user_data["Status"].presence&.strip

    # Validate that the provided status is allowed for this deal. If not, raise an error.
    raise "Status '#{status_value}' is not allowed. Use one of: #{allowed_statuses.join(', ')}" if status_value.present? && allowed_statuses.exclude?(status_value)

    deal_investor.assign_attributes(
      entity_id:,
      status: status_value || allowed_statuses.first,
      tier: user_data["Tier"].presence&.strip,
      deal_lead: user_data["Deal Lead"].presence&.strip,
      source: user_data["Source"].presence&.strip,
      tags: user_data["Tags"].presence&.strip,
      primary_amount_cents: primary_cents,
      secondary_investment_cents: secondary_cents,
      pre_money_valuation_cents: pre_money_cents,
      import_upload_id: import_upload.id
    )

    # Store unmapped columns as custom fields
    if custom_headers.any? && deal_investor.respond_to?(:json_fields)
      deal_investor.json_fields ||= {}
      custom_headers.each do |col|
        key = FormCustomField.to_name(col)
        deal_investor.json_fields[key] = user_data[col]
      end
    end

    deal_investor.save!

    # Create DealActivity records from templates only for brand-new investors
    create_deal_activities(deal, deal_investor, entity_id, import_upload.user_id) if deal_investor.previously_new_record?

    import_upload.processed_row_count += 1
    result_row << "Success"
  rescue StandardError => e
    Rails.logger.error e.message
    import_upload.failed_row_count += 1
    result_row << "Error: #{e.message}"
  end

  # helper method to get allowed statuses for a deal, defaulting to DealInvestor::STATUS if not set
  def allowed_statuses_for(deal)
    deal.deal_investor_status.presence || DealInvestor::STATUS
  end

  def create_deal_activities(deal, deal_investor, entity_id, user_id = nil)
    DealActivity.templates(deal).each do |template|
      activity = DealActivity.where(
        deal_id: deal.id,
        deal_investor_id: deal_investor.id,
        template_id: template.id
      ).first_or_initialize

      next unless activity.new_record?

      activity.assign_attributes(
        entity_id:,
        title: template.title,
        status: "incomplete",
        days: template.days || 0,
        sequence: template.sequence,
        template_id: template.id
      )
      activity.save!
    end

    first_step = deal_investor.deal_activities.order(:sequence).first
    return unless first_step&.template_id

    deal_investor.update_column(:deal_activity_id, first_step.template_id)

    # Genrate tasks for the first step asynchronously, passing the user_id for tracking who performed the action
    GenerateDealStepTasksJob.perform_later(deal_investor.id, user_id, first_step.id)
  end

  # -----------------------------------------------------------------------
  # Sheet 2 — Deal Steps
  # Updates DealActivity statuses; row 1 = headers (investor name + step titles)
  # -----------------------------------------------------------------------
  def process_deal_steps(import_upload, sheet)
    deal      = import_upload.owner
    entity_id = import_upload.entity_id
    headers   = sheet[:headers]  # ["Deal Investor", "Deck Sent", "Meeting 1", ...]
    step_titles = headers[1..]   # drop the "Deal Investor" column

    sheet[:data][1..].each do |row|
      investor_name = row[0].to_s.strip
      next if investor_name.blank?

      investor = Investor.where(investor_name:, entity_id:).first
      next if investor.nil?

      deal_investor = DealInvestor.find_by(deal_id: deal.id, investor_id: investor.id)
      next if deal_investor.nil?

      step_titles.each_with_index do |title, idx|
        next if title.blank?

        # The status value is expected to be in the next column (idx + 1) corresponding to this title
        status_value = row[idx + 1].to_s.strip
        next if status_value.blank?

        # Case-insensitive match against the activity title
        activity = deal_investor.deal_activities.find { |a| a.title.casecmp?(title) }
        next if activity.nil?

        mapped_status = map_activity_status(status_value)
        activity.update_column(:status, mapped_status) if mapped_status
      end

      import_upload.processed_row_count += 1
    rescue StandardError => e
      Rails.logger.error "Deal Steps row error for '#{investor_name}': #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  # Maps the human-readable template values to DealActivity enum keys
  def map_activity_status(value)
    { "complete" => "complete", "incomplete" => "incomplete", "skip" => "skip" }[value.downcase]
  end

  # -----------------------------------------------------------------------
  # Sheet 3 — Notes
  # Creates Note records (and optional Reminder) for each row.
  # Expected headers: Deal Investor, On, Details, Tags,
  #                   Reminder Emails, Reminder Date
  # -----------------------------------------------------------------------
  def process_notes(import_upload, sheet)
    # Get the owner deal and entity_id for the notes
    deal      = import_upload.owner
    entity_id = import_upload.entity_id
    headers   = sheet[:headers]

    sheet[:data][1..].each do |row|
      user_data = headers.zip(row).to_h
      investor_name = user_data["Deal Investor"].to_s.strip
      next if investor_name.blank?

      investor = Investor.where(investor_name:, entity_id:).first
      next if investor.nil?

      # We need to find the DealInvestor record for this investor in the context of the current deal, because notes are associated with DealInvestor, not directly with Investor.
      deal_investor = DealInvestor.find_by(deal_id: deal.id, investor_id: investor.id)
      raise "DealInvestor for investor '#{investor_name}' not found in this deal" if deal_investor.nil?

      details_text = user_data["Details"].to_s.strip
      next if details_text.blank?

      # Attach the note to the DealInvestor, and create a Reminder if either Reminder Emails or Reminder Date is present.
      note = Note.new(
        entity_id:,
        owner_id: deal_investor.id,
        owner_type: "DealInvestor",
        user_id: import_upload.user_id,
        on: parse_date(user_data["On"]),
        tags: user_data["Tags"].presence&.strip
      )
      note.details = details_text
      note.save!

      # Create a reminder if email or due_date is present
      reminder_email = user_data["Reminder Emails"].presence&.strip
      reminder_date  = parse_date(user_data["Reminder Date"])
      if reminder_email.present? || reminder_date.present?
        Reminder.create!(
          owner: note,
          entity_id:,
          email: reminder_email,
          due_date: reminder_date,
          note: details_text # Reminder#note (text field) must be present
        )
      end

      import_upload.processed_row_count += 1
    rescue StandardError => e
      Rails.logger.error "Notes row error for '#{investor_name}': #{e.message}"
      import_upload.failed_row_count += 1
    end
  end

  # -----------------------------------------------------------------------
  # Helpers
  # -----------------------------------------------------------------------

  def parse_money(value)
    return 0 if value.blank?

    value.to_s.gsub(/[^0-9.]/, "").to_d * 100
  end

  def parse_date(value)
    return nil if value.blank?
    return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

    Date.local_parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
