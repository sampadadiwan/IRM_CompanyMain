class ImportKpi < ImportUtil
  include Interactor

  STANDARD_HEADERS = ["Name", "Period", "Value", "As Of", "Notes"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(import_upload, _context)
    # This recomputes the KPI percentage change for all KPIs of this entity
    KpiPercentageChangeJob.perform_later(import_upload.entity_id, import_upload.user_id)
  end

  def save_kpi(user_data, import_upload, custom_field_headers)
    name = user_data['Name'].strip
    period = user_data['Period'].strip
    value = user_data['Value']
    as_of = Date.parse(user_data['As Of'].to_s)
    notes = user_data['Notes']
    entity_id = import_upload.entity_id

    kpi_report = KpiReport.find_or_initialize_by(as_of:, entity_id:)
    if kpi_report.new_record?
      kpi_report.user_id = import_upload.user_id
      kpi_report.form_type = kpi_report.entity.form_types.where(name: "KpiReport").first
      kpi_report.save!
    end

    Rails.logger.debug kpi_report.to_json
    Rails.logger.debug { "############ kpi_report = #{kpi_report.errors.full_messages}" }

    kpi = Kpi.where(name:, period:, entity_id:, kpi_report_id: kpi_report.id).first
    attach_uploaded_document(kpi_report, import_upload)

    if kpi.present?
      Rails.logger.debug { "Kpi with name #{name} already exists for entity #{import_upload.entity_id}" }
      raise "Kpi with already exists."
    else

      Rails.logger.debug user_data

      kpi = Kpi.new(name:, period:, notes:, value:, display_value: value, entity_id:,
                    kpi_report_id: kpi_report.id, import_upload_id: import_upload.id)
      setup_custom_fields(user_data, kpi, custom_field_headers)

      Rails.logger.debug { "Saving kpi with name '#{kpi.name}'" }
      kpi.save!

    end

    true
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

  def process_row(headers, custom_field_headers, row, import_upload, _context)
    # create hash from headers and cells

    user_data = [headers, row].transpose.to_h
    Rails.logger.debug { "#### user_data = #{user_data}" }
    begin
      if save_kpi(user_data, import_upload, custom_field_headers)
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
