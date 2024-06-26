class ImportKpi < ImportUtil
  STANDARD_HEADERS = ["Name", "Period", "Value", "As Of", "Notes"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(ctx, import_upload:, **)
    super
    # This recomputes the KPI percentage change for all KPIs of this entity
    KpiPercentageChangeJob.perform_later(import_upload.entity_id, import_upload.user_id)
    InvestorKpiMapping.create_from(import_upload.entity, import_upload.entity.kpi_reports.last) if import_upload.entity.kpi_reports.last.present?

    true
  end

  def save_row(user_data, import_upload, custom_field_headers)
    name, value, _, _, notes = get_data(user_data)
    entity_id = import_upload.entity_id

    portfolio_company = nil
    if user_data['Portfolio Company'].present?
      portfolio_company = import_upload.entity.investors.where(name: user_data['Portfolio Company'], category: "Portfolio Company").first
      raise "Portfolio Company #{user_data['Portfolio Company']} not found" if portfolio_company.blank?
    elsif import_upload.owner_type == "Investor"
      portfolio_company = import_upload.owner
    end

    # This is incase we are uploading for a PC, then the Kpi has to have that entity_id
    if portfolio_company.present?
      entity_id = portfolio_company.investor_entity_id
      owner = import_upload.entity
    end

    kpi_report = setup_kpi_report(entity_id, portfolio_company, owner, user_data, import_upload)

    kpi = Kpi.where(name:, entity_id:, kpi_report_id: kpi_report.id, portfolio_company:, owner:).first

    if kpi.present?
      Rails.logger.debug { "Kpi with name #{name} already exists for entity #{import_upload.entity_id}" }
      raise "Kpi with already exists."
    else

      Rails.logger.debug user_data

      kpi = Kpi.new(name:, notes:, value:, display_value: value, entity_id:, owner:,
                    kpi_report_id: kpi_report.id, import_upload_id: import_upload.id, portfolio_company:)
      setup_custom_fields(user_data, kpi, custom_field_headers - ["Tag"])

      Rails.logger.debug { "Saving kpi with name '#{kpi.name}'" }
      kpi.save!

    end

    true
  end

  def setup_kpi_report(entity_id, portfolio_company, owner, user_data, import_upload)
    _, _, as_of, period, = get_data(user_data)
    tag = user_data['Tag'].presence || ""

    kpi_report = KpiReport.find_or_initialize_by(as_of:, period:, entity_id:, portfolio_company:, owner:, tag_list: tag)
    if kpi_report.new_record?
      # Save it as a new record
      kpi_report.user_id = import_upload.user_id
      kpi_report.form_type = import_upload.entity.form_types.where(name: "KpiReport").first
      kpi_report.save!

      # If this is created for a portfolio_company, lets give the investor access rights
      create_access_right(portfolio_company, kpi_report) if portfolio_company.present?
    end
    # Attach the uploaded document to the KpiReport
    attach_uploaded_document(kpi_report, import_upload)

    kpi_report
  end

  def create_access_right(portfolio_company, kpi_report)
    portfolio_entity = portfolio_company.investor_entity
    investor = portfolio_entity.investors.find_or_initialize_by(investor_entity_id: portfolio_company.entity_id)
    if investor.new_record?
      investor.investor_name = portfolio_company.entity.name
      investor.primary_email = portfolio_company.entity.primary_email
      investor.category = "Investor"
      investor.save!
    end

    Rails.logger.debug { "Creating access right for #{investor} to KpiReport #{kpi_report.id}" }

    access_right = portfolio_entity.access_rights.find_or_initialize_by(access_to_investor_id: investor.id, entity_id: kpi_report.entity_id, owner: kpi_report, access_type: "KpiReport", notify: false)
    access_right.save! if access_right.new_record?
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
