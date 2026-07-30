class GeneratePortfolioReportExtractsJob < LlmReportJob
  include ActionView::Helpers::TextHelper

  queue_as :low

  # Bulk entry point: generates an extract for each of the given portfolio companies, collecting
  # per-company failures instead of aborting the run, then reports once for the whole batch.
  #
  # Callers that need the result for a single company (PortfolioReportJob) should call
  # #generate_extract directly — it returns that company's extract and error message without this
  # method's batch summary toast and error email.
  #
  # @param portfolio_company_ids [Array<Integer>] The portfolio companies to generate extracts for.
  # @param portfolio_report_id [Integer] The portfolio report being generated.
  # @param start_date [Date] The start date for the report.
  # @param end_date [Date] The end date for the report.
  # @param user_id [Integer] The ID of the user initiating the generation.
  # @return [Array<Hash>] The collected {msg:, model:} errors — empty when every company succeeded.
  def perform(portfolio_company_ids, portfolio_report_id, start_date, end_date, user_id)
    @errors = []
    portfolio_report = PortfolioReport.find(portfolio_report_id)
    portfolio_companies = Investor.where(id: Array(portfolio_company_ids))

    portfolio_companies.each_with_index do |portfolio_company, index|
      # Per-company progress toast (1/n). generate_extract runs with notify: false so this is the
      # single progress message per company — without this send the toast is never shown.
      progress = "Generating extract for #{portfolio_company.name} for report #{portfolio_report}: #{index + 1}/#{portfolio_companies.size}"
      send_notification(progress, user_id, "success")
      _extract, msg = generate_extract(portfolio_company, portfolio_report, start_date, end_date, user_id, notify: false)
      @errors << { msg: msg, model: portfolio_company.to_s } if msg.present?
    rescue StandardError => e
      msg = "Error generating extract for #{portfolio_company} for report #{portfolio_report}: #{e.message}"
      Rails.logger.error(msg)
      @errors << { msg: msg, model: portfolio_company.to_s }
    end

    notify_completion(portfolio_report, portfolio_companies.size, user_id)
    @errors
  end

  # Generates a report extract for a given portfolio company.
  # The documents are taken automatically from the company's latest KPI report that owns
  # documents (see #source_documents); their ids are persisted on the extract so they can be
  # replayed as audits in the report. An extract is ALWAYS created — even when no documents
  # exist — so the report is generated with a single "No data available" section the user edits.
  #
  # @param portfolio_company [PortfolioCompany] The portfolio company for which to generate the extract.
  # @param portfolio_report [PortfolioReport] The portfolio report being generated.
  # @param start_date [Date] The start date for the report.
  # @param end_date [Date] The end date for the report.
  # @param user_id [Integer] The ID of the user initiating the report generation.
  # @return [Array(PortfolioReportExtract, String|nil)] A tuple of the created PortfolioReportExtract
  #   and an explanatory message when no documents were found (nil otherwise).
  def generate_extract(portfolio_company, portfolio_report, start_date, end_date, user_id, notify: true)
    # Notify the user that extract generation has started
    msg = "Generating extract for #{portfolio_company.name} for report #{portfolio_report}"
    send_notification(msg, user_id) if notify

    # The documents to feed the LLM: all source docs of the latest documented KPI report.
    documents = source_documents(portfolio_company, start_date, end_date)
    notes = filtered_notes(portfolio_company, portfolio_report, start_date, end_date)

    # Always create the extract, storing the documents it was built from. When there are no
    # documents the extract is left with data: nil and the report shows "No data available".
    portfolio_report_extract = PortfolioReportExtract.create!(
      entity_id: portfolio_report.entity_id,
      portfolio_company_id: portfolio_company.id,
      portfolio_report_id: portfolio_report.id,
      portfolio_report_section_id: nil, start_date: start_date, end_date: end_date,
      source_document_ids: documents.map(&:id)
    )

    if documents.blank?
      msg = "No documents found for #{portfolio_company.name} for #{portfolio_report}"
      Rails.logger.debug { msg }
      send_notification(msg, user_id, "danger")
      return [portfolio_report_extract, msg]
    end

    # Notify the user that information is being sent to the LLM
    msg = "Sending the extracted information to the LLM for processing"
    send_notification(msg, user_id) if notify

    # Define LLM instructions for formatting the output
    llm_instructions = get_llm_instructions(portfolio_report)

    # Call the LLM (Large Language Model) with the extracted documents, notes, and instructions
    result = DocLlmContext.call(model: portfolio_report_extract,
                                documents: documents,
                                notes: notes,
                                llm_instructions:)

    # Log the LLM result for debugging purposes
    Rails.logger.debug result
    # Notify the user that information has been extracted
    msg = "Extracted information for #{portfolio_company.name} for report #{portfolio_report}"
    send_notification(msg, user_id) if notify

    # Update the portfolio report extract with the data received from the LLM
    portfolio_report_extract.update(data: result[:extracted_info])
    # Return the created and updated portfolio report extract
    [portfolio_report_extract, nil]
  end

  def get_llm_instructions(portfolio_report)
    sections = portfolio_report.portfolio_report_sections

    section_names = sections.map(&:name)

    # Human-readable "what to do" per section
    section_tasks_text = sections.map do |section|
      %("#{section.name}": #{section.data.to_s.strip})
    end.join("\n")

    # JSON skeleton with the exact keys you want
    json_skeleton = "{\n#{section_names.map { |name| %(  "#{name}": []) }.join(",\n")}\n}"

    <<~INSTRUCTIONS
      You are generating a JSON object for a portfolio report.

      For each section, follow the described task:

      #{section_tasks_text}

      You MUST respond with a single JSON object with exactly the following keys:

      #{section_names.map { |n| %(- "#{n}") }.join("\n")}

      Rules:
      - Do NOT rename, remove, or add any keys.
      - The top-level structure MUST be a JSON object.
      - Each value MUST be an array of strings (each string is one point).
      - Do NOT nest JSON objects or arrays inside items.
      - Do NOT include any newline (\\n) or tab (\\t) characters inside an item.
      - Do NOT include markdown fences like ```json.

      The JSON must follow this structure (values are examples only):

      #{json_skeleton}
    INSTRUCTIONS
  end

  private

  # One summary for the whole batch, so the per-company progress toasts are followed by a clear
  # "the run is over" message. A company whose documents or notes are missing is reported as an
  # error here (it produced an empty extract), listed in one danger toast and emailed out.
  def notify_completion(portfolio_report, count, user_id)
    if @errors.any?
      msg = "Extract generation completed with the following #{@errors.count} errors.
      <div>
      #{@errors.pluck(:msg).join('<br>')}</div>"
      send_notification(msg, user_id, "danger")
      EntityMailer.with(entity_id: portfolio_report.entity_id, user_id:, error_msg: @errors).doc_gen_errors.deliver_now
    else
      send_notification("Extract generation completed for #{pluralize(count, 'portfolio company')}.", user_id, "success")
    end
  end

  # The source documents used to build the extract: every non-generated (source) document
  # owned by the portfolio company's most-recently-documented KPI report.
  #
  # Why "latest document wins": users used to hand-pick KPI reports/documents per run, which was
  # error-prone and often produced empty extracts. Now the newest KPI-report document in the date
  # range decides which KPI report to use — even if it belongs to a monthly report while an older
  # quarterly report also owns documents (known behaviour). We then feed ALL of that report's
  # non-generated documents to the LLM (not just the named ones used for the lookup), so
  # attachments outside the form's File fields still contribute to the narrative.
  #
  # Documents are deliberately NOT filtered by portfolio report tags: an untagged document would
  # be silently dropped and yield an empty extract. Tag filtering still applies to notes (see
  # #filtered_notes), where the report's tags express a real content preference.
  #
  # @param portfolio_company [Investor] The portfolio company to source documents for.
  # @return [Array<Document>] All non-generated documents of the chosen KPI report.
  def source_documents(portfolio_company, start_date, end_date)
    document_names = []
    form_type = portfolio_company.entity.form_types.where(name: "KpiReport").order(:id).last
    if form_type.present?
      form_custom_fields = FormCustomField.where(form_type_id: form_type.id, field_type: "File")
      document_names = form_custom_fields.map { |x| x.name.titleize }
    end
    document_names << "KPIs"
    latest = Document.where(
      owner_type: "KpiReport",
      owner_id: KpiReport.where(entity_id: portfolio_company.entity_id, portfolio_company_id: portfolio_company.id, as_of: start_date..end_date).select(:id),
      name: document_names
    ).not_generated.order(created_at: :desc).first

    return [] if latest.nil?

    latest.owner.documents.not_generated
  end

  # Retrieves the company's notes within the date range, filtered by the report's tags.
  #
  # @param portfolio_company [Investor] The portfolio company to retrieve notes for.
  # @param portfolio_report [PortfolioReport] The report whose tags scope the notes.
  # @param start_date [Date] The start date for filtering notes.
  # @param end_date [Date] The end date for filtering notes.
  # @return [Array<Note>] A list of notes.
  def filtered_notes(portfolio_company, portfolio_report, start_date, end_date)
    report_tags = portfolio_report.tags.to_s.split(',').map(&:strip)
    notes = portfolio_company.notes.where(on: start_date..end_date)
    filter_by_report_tags(notes, report_tags)
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
end
