class ImportKpi < ImportUtil
  STANDARD_HEADERS = ["Name", "Period", "Value", "As Of", "Notes"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(ctx, import_upload:, **)
    super
    # This recomputes the KPI percentage change for all KPIs of this entity
    KpiPercentageChangeJob.perform_later(import_upload.entity_id, import_upload.user_id)
    true
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    name, value, _, _, notes = get_data(user_data)
    import_upload.entity_id

    portfolio_company = nil
    if user_data['Portfolio Company'].present?
      portfolio_company = import_upload.entity.investors.where(name: user_data['Portfolio Company'], category: "Portfolio Company").first
      raise "Portfolio Company #{user_data['Portfolio Company']} not found" if portfolio_company.blank?
    elsif import_upload.owner_type == "KpiReport"
      portfolio_company = import_upload.owner.portfolio_company
    elsif import_upload.owner_type == "Investor"
      portfolio_company = import_upload.owner
    end

    entity_id = import_upload.entity_id
    kpi_report = setup_kpi_report(entity_id, portfolio_company, user_data, import_upload)

    kpi = Kpi.where(name:, entity_id:, kpi_report_id: kpi_report.id, portfolio_company:).first

    if kpi.present?
      Rails.logger.debug { "Kpi with name #{name} already exists for entity #{import_upload.entity_id}" }
      raise "Kpi with already exists."
    else

      Rails.logger.debug user_data

      kpi = Kpi.new(name:, notes:, value:, display_value: value, entity_id:, portfolio_company:,
                    kpi_report_id: kpi_report.id, import_upload_id: import_upload.id)
      setup_custom_fields(user_data, kpi, custom_field_headers - ["Tag"])

      Rails.logger.debug { "Saving kpi with name '#{kpi.name}'" }
      kpi.save!

    end

    true
  end

  def setup_kpi_report(entity_id, portfolio_company, user_data, import_upload)
    _, _, as_of, period, = get_data(user_data)
    tag = user_data['Tag'].presence || ""

    kpi_report = KpiReport.find_or_initialize_by(as_of:, period:, entity_id:, portfolio_company:, tag_list: tag)
    if kpi_report.new_record?
      # Save it as a new record
      kpi_report.user_id = import_upload.user_id
      kpi_report.form_type = import_upload.entity.form_types.where(name: "KpiReport").first
      kpi_report.save!
    end
    # Attach the uploaded document to the KpiReport
    attach_uploaded_document(kpi_report, import_upload)

    kpi_report
  end

  def get_data(user_data)
    name = user_data['Name'].strip
    value = user_data['Value']
    as_of = Date.parse(user_data['As Of'].to_s)
    notes = user_data['Notes']
    period = user_data['Period']

    [name, value, as_of, period, notes]
  end

  def attach_uploaded_document(kpi_report, import_upload)
    name = "#{kpi_report} Uploaded"
    existing = kpi_report.documents.where(name:).first
    if existing.present?
      Rails.logger.debug "Uploaded Kpis Document already exists"
    else
      Document.create(name:, owner: kpi_report, user_id: import_upload.user_id, entity_id: kpi_report.entity_id, file_data: import_upload.import_file_data, import_upload_id: import_upload.id, orignal: true, send_email: false)
    end
  end
end
