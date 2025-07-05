class PortfolioReportJob < LlmReportJob
  queue_as :low

  # This job is called to generate a portfolio report for a given date range
  def perform(portfolio_report_id, start_date, end_date, user_id, portfolio_company_id: nil, kpi_reports_map: nil)
    portfolio_report = PortfolioReport.find(portfolio_report_id)

    # Get the portfolio_companies for the entity
    portfolio_companies = portfolio_report.entity.investors.portfolio_companies
    if portfolio_company_id.present?
      portfolio_companies = portfolio_companies.where(id: portfolio_company_id)
    elsif portfolio_report.tags
      # Are we running this for specific tags?
      portfolio_report_tags = portfolio_report.tags.split(",").map(&:strip)
      portfolio_companies = portfolio_companies.select do |portfolio_company|
        portfolio_company.tag_list.split(',').map(&:strip).intersect?(portfolio_report_tags)
      end
    end

    portfolio_companies.each do |portfolio_company|
      begin
        # generate_section_extracts(portfolio_company, portfolio_report, start_date, end_date)
        portfolio_report_extract = generate_report_extracts(portfolio_company, portfolio_report, start_date, end_date, user_id, kpi_reports_map)

        next if portfolio_report_extract.blank?
      rescue StandardError => e
        msg = "Error generating report for #{portfolio_company.name} for report #{portfolio_report}: #{e.message}"
        send_notification(msg, user_id, "danger")
        raise e
      end

      # Now generate the actual report using the templates
      PortfolioReportDocGenJob.perform_later(
        portfolio_report_extract.id,
        start_date, end_date, user_id
      )
    end
  end

  def generate_report_extracts(portfolio_company, portfolio_report, start_date, end_date, user_id, kpi_reports_map)
    msg = "Generating extract for #{portfolio_company.name} for report #{portfolio_report}"
    send_notification(msg, user_id)

    filtered_documents, filtered_notes = get_docs_notes(portfolio_company, portfolio_report,
                                                        start_date, end_date, kpi_reports_map)

    if filtered_documents.empty?
      Rails.logger.debug { "No documents found for #{portfolio_company.name} for report #{portfolio_report}" }
      nil
    else
      # Create a PortfolioReportExtract record to capture the output
      portfolio_report_extract = PortfolioReportExtract.create!(
        entity_id: portfolio_report.entity_id,
        portfolio_company_id: portfolio_company.id,
        portfolio_report_id: portfolio_report.id,
        portfolio_report_section_id: nil, start_date: start_date, end_date: end_date
      )

      # Call the LLM to generate the report
      json_output = {}
      portfolio_report.portfolio_report_sections.each do |section|
        json_output[section.name] = "#{section.data} Extract the information as a array"
      end

      msg = "Sending the extracted information to the LLM for processing"
      send_notification(msg, user_id)

      llm_instructions = "Format your output as json in the format #{json_output}. Do not generate nested json, just one level. Do not add any \n (newlines), \t (tabs) within an item and do not add ```json to the output."
      result = DocLlmContext.wtf?(model: portfolio_report_extract,
                                  documents: filtered_documents,
                                  notes: filtered_notes,
                                  llm_instructions:)

      # Save the result in the extract
      Rails.logger.debug result
      msg = "Extracted information from the documents and notes"
      send_notification(msg, user_id)

      portfolio_report_extract.update(data: result[:extracted_info])
      portfolio_report_extract

    end
  end

  def get_docs_notes(portfolio_company, portfolio_report, start_date, end_date, kpi_reports_map)
    # Convert the section's comma separated tags to an array for matching
    report_tags = portfolio_report.tags.split(',').map(&:strip)

    # kpi_reports_map is an array of hashes with the following structure
    # [
    #   { period: "monthly", as_of: "2021-01-01", add_docs: true },
    #   { period: "monthly", as_of: "2021-02-01", add_docs: true },
    # ]
    # We need to filter the documents based on the KPI reports matching the kpi_reports_map
    if kpi_reports_map.blank?
      send_notification("No KPI reports provided for documents to include", user_id, "danger")
      return [[], []]
    else

      # Filter the KPI reports based on the map
      kpi_reports_add_docs_or_clause = KpiReport.none

      kpi_reports_map.each do |entry|
        # We need to add the documents for these KPI report
        next if entry[:add_docs].blank?

        as_of = Date.parse(entry[:as_of])
        kpi_reports_add_docs_or_clause = kpi_reports_add_docs_or_clause.or(
          KpiReport.where(period: entry[:period], as_of: as_of.all_month)
        )
      end

      # Get the KPI reports for the portfolio company, which match the kpi_reports_map
      kpi_reports_add_docs = portfolio_company.portfolio_kpi_reports.merge(kpi_reports_add_docs_or_clause)
      # Get the documents for the KPI reports, which are not generated & only for the kpi_reports_add_docs
      documents = Document.where(owner_type: "KpiReport", owner_id: kpi_reports_add_docs.pluck(:id)).not_generated

    end

    # Get the notes for the KPI reports
    notes = portfolio_company.notes.where(created_at: start_date..end_date)

    # Filter the records that contain any matching tag
    if report_tags.present?
      filtered_documents = documents.select do |doc|
        doc.tag_list.present? && doc.tag_list.split(',').map(&:strip).intersect?(report_tags)
      end
      filtered_notes = notes.select do |note|
        note.tags.present? && note.tags.split(',').map(&:strip).intersect?(report_tags)
      end
    else
      filtered_documents = documents
      filtered_notes = notes
    end

    # We only allow for PDF and CSV documents for now
    filtered_documents = filtered_documents.select { |doc| doc.pdf? || doc.csv? }

    Rails.logger.debug { "Filtered Documents: #{filtered_documents.count}, #{filtered_documents.map(&:id)}" }
    Rails.logger.debug { "Filtered Notes: #{filtered_notes.count}, #{filtered_notes.map(&:id)}" }

    [filtered_documents, filtered_notes]
  end
end
