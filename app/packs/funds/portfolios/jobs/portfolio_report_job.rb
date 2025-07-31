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

  # Generates report extracts for a given portfolio company.
  # This method retrieves relevant documents and notes, creates a PortfolioReportExtract record,
  # calls the LLM to process the information, and saves the extracted data.
  #
  # @param portfolio_company [PortfolioCompany] The portfolio company for which to generate the extract.
  # @param portfolio_report [PortfolioReport] The portfolio report being generated.
  # @param start_date [Date] The start date for the report.
  # @param end_date [Date] The end date for the report.
  # @param user_id [Integer] The ID of the user initiating the report generation.
  # @param kpi_reports_map [Array<Hash>] A map of KPI reports to include documents from.
  # @return [PortfolioReportExtract, nil] The created PortfolioReportExtract object, or nil if no documents are found.
  def generate_report_extracts(portfolio_company, portfolio_report, start_date, end_date, user_id, kpi_reports_map)
    # Notify the user that extract generation has started
    msg = "Generating extract for #{portfolio_company.name} for report #{portfolio_report}"
    send_notification(msg, user_id)

    # Retrieve and filter documents and notes using the helper method
    filtered_documents, filtered_notes = get_docs_notes(portfolio_company, portfolio_report,
                                                        start_date, end_date, kpi_reports_map)

    # If no filtered documents are found, log a debug message and return nil
    if filtered_documents.empty?
      Rails.logger.debug { "No documents found for #{portfolio_company.name} for report #{portfolio_report}" }
      nil
    else
      # Create a new PortfolioReportExtract record to store the generated output
      portfolio_report_extract = PortfolioReportExtract.create!(
        entity_id: portfolio_report.entity_id,
        portfolio_company_id: portfolio_company.id,
        portfolio_report_id: portfolio_report.id,
        portfolio_report_section_id: nil, start_date: start_date, end_date: end_date
      )

      # Prepare the JSON output structure based on portfolio report sections
      json_output = {}
      portfolio_report.portfolio_report_sections.each do |section|
        json_output[section.name] = "#{section.data} Extract the information as a array"
      end

      # Notify the user that information is being sent to the LLM
      msg = "Sending the extracted information to the LLM for processing"
      send_notification(msg, user_id)

      # Define LLM instructions for formatting the output
      llm_instructions = "Format your output as json in the format #{json_output}. Do not generate nested json, just one level. Do not add any \n (newlines), \t (tabs) within an item and do not add ```json to the output."

      # Call the LLM (Large Language Model) with the extracted documents, notes, and instructions
      result = DocLlmContext.wtf?(model: portfolio_report_extract,
                                  documents: filtered_documents,
                                  notes: filtered_notes,
                                  llm_instructions:)

      # Log the LLM result for debugging purposes
      Rails.logger.debug result
      # Notify the user that information has been extracted
      msg = "Extracted information from the documents and notes"
      send_notification(msg, user_id)

      # Update the portfolio report extract with the data received from the LLM
      portfolio_report_extract.update(data: result[:extracted_info])
      # Return the created and updated portfolio report extract
      portfolio_report_extract
    end
  end

  # Retrieves and filters documents and notes for a portfolio report.
  # This method orchestrates the calls to several helper methods to gather,
  # filter, and prepare the necessary documents and notes for LLM processing.
  #
  # @param portfolio_company [PortfolioCompany] The portfolio company associated with the report.
  # @param portfolio_report [PortfolioReport] The portfolio report being generated.
  # @param start_date [Date] The start date for filtering documents and notes.
  # @param end_date [Date] The end date for filtering documents and notes.
  # @param kpi_reports_map [Array<Hash>] A map of KPI reports to include documents from.
  # @return [Array<Array>] A tuple containing two arrays: [filtered_documents, filtered_notes].
  def get_docs_notes(portfolio_company, portfolio_report, start_date, end_date, kpi_reports_map)
    # Convert report tags from a comma-separated string to an array for filtering
    report_tags = portfolio_report.tags.split(',').map(&:strip)

    # Extract KPI-related documents based on the provided map
    documents = extract_kpi_documents(portfolio_company, kpi_reports_map)
    # If no documents are found, return empty arrays early to avoid further processing
    return [[], []] if documents.blank?

    # Retrieve notes for the portfolio company within the specified date range
    notes = get_portfolio_notes(portfolio_company, start_date, end_date)

    # Filter both documents and notes by the report's tags
    filtered_documents = filter_by_report_tags(documents, report_tags)
    filtered_notes = filter_by_report_tags(notes, report_tags)

    # Further filter documents to include only PDF or CSV types
    filtered_documents = filter_by_document_type(filtered_documents)

    # Log the counts and IDs of the filtered documents and notes for debugging
    Rails.logger.debug { "Filtered Documents: #{filtered_documents.count}, #{filtered_documents.map(&:id)}" }
    Rails.logger.debug { "Filtered Notes: #{filtered_notes.count}, #{filtered_notes.map(&:id)}" }

    # Return the filtered documents and notes
    [filtered_documents, filtered_notes]
  end

  private

  # Extracts KPI-related documents for a given portfolio company based on a map of KPI reports.
  #
  # @param portfolio_company [PortfolioCompany] The portfolio company to extract documents for.
  # @param kpi_reports_map [Array<Hash>] A map of KPI reports with period, as_of, and add_docs flag.
  # @return [Array<Document>] A list of filtered documents.
  def extract_kpi_documents(portfolio_company, kpi_reports_map)
    if kpi_reports_map.blank?
      send_notification("No KPI reports provided for documents to include", user_id, "danger")
      return []
    end

    kpi_reports_add_docs_or_clause = KpiReport.none
    kpi_reports_map.each do |entry|
      next if entry[:add_docs].blank?

      as_of = Date.parse(entry[:as_of])
      kpi_reports_add_docs_or_clause = kpi_reports_add_docs_or_clause.or(
        KpiReport.where(period: entry[:period], as_of: as_of.all_month)
      )
    end

    kpi_reports_add_docs = portfolio_company.portfolio_kpi_reports.merge(kpi_reports_add_docs_or_clause)
    Document.where(owner_type: "KpiReport", owner_id: kpi_reports_add_docs.pluck(:id)).not_generated
  end

  # Retrieves notes for a given portfolio company within a specified date range.
  #
  # @param portfolio_company [PortfolioCompany] The portfolio company to retrieve notes for.
  # @param start_date [Date] The start date for filtering notes.
  # @param end_date [Date] The end date for filtering notes.
  # @return [Array<Note>] A list of notes.
  def get_portfolio_notes(portfolio_company, start_date, end_date)
    portfolio_company.notes.where(created_at: start_date..end_date)
  end

  # Filters a collection of records (documents or notes) based on matching report tags.
  #
  # @param records [Array<ActiveRecord::Base>] The records to filter.
  # @param report_tags [Array<String>] The tags to match against.
  # @return [Array<ActiveRecord::Base>] A list of filtered records.
  def filter_by_report_tags(records, report_tags)
    return records if report_tags.blank?

    records.select do |record|
      record.tag_list.present? && record.tag_list.split(',').map(&:strip).intersect?(report_tags)
    end
  end

  # Filters a collection of documents to include only PDF or CSV types.
  #
  # @param documents [Array<Document>] The documents to filter.
  # @return [Array<Document>] A list of filtered documents (PDF or CSV).
  def filter_by_document_type(documents)
    documents.select { |doc| doc.pdf? || doc.csv? }
  end
end
