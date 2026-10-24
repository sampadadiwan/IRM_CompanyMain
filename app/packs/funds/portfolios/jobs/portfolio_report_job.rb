class PortfolioReportJob < LlmReportJob
  queue_as :low

  # One entry of the run's ordered list: a report and the template chosen for it.
  Part = Struct.new(:report, :template_id)

  # This job is called to generate a portfolio report for a given date range.
  # A report is ALWAYS generated for every company: when a company has no extract and
  # generate_missing_extracts is false, an empty extract is used and the report renders a
  # single "No data available" section. Pass generate_missing_extracts: true to instead call
  # the LLM to build an extract for companies that don't have one yet.
  #
  # The run builds an ordered list of parts. The first part is the positional report and template;
  # additional_parts carries the rest ({ "portfolio_report_id", "template_id" } hashes, in row order).
  # A normal report contributes one piece per company (A-Z); a consolidated report contributes one
  # piece for all companies. The pieces are joined, in order, into one combined document.
  # E9: a job queued before the list existed has no additional_parts and runs as a list of one.
  def perform(portfolio_report_id, template_id, start_date, end_date, user_id, portfolio_company_ids: nil,
              generate_missing_extracts: false, additional_parts: [])
    Chewy.strategy(:sidekiq) do
      @errors = []
      @companies_without_extracts = []
      @extracts = {}
      portfolio_report = PortfolioReport.find(portfolio_report_id)
      parts = parts_for(portfolio_report, template_id, additional_parts)
      portfolio_companies = resolve_companies(portfolio_report, portfolio_company_ids)

      # Consolidated pieces are written here, and the folder is removed when the run ends
      run_dir = Rails.root.join("tmp", "portfolio_report_packet", SecureRandom.hex(8)).to_s
      FileUtils.mkdir_p(run_dir)

      # Pieces in their final order: company Documents and consolidated .docx paths
      sources = []
      parts.each_with_index do |part, index|
        if part.report.consolidated?
          # H5, X7: a consolidated part is built once for all companies; a failure is recorded and the rest carry on
          path = consolidated_file(part, portfolio_companies, File.join(run_dir, "part_#{index}"), start_date, end_date, user_id)
          sources << path if path
        else
          sources.concat(company_documents(part, portfolio_companies, start_date, end_date, user_id, generate_missing_extracts))
        end
      end

      final_document = final_document(sources, parts.first, portfolio_report, portfolio_companies, start_date, end_date, user_id)

      # Only genuine failures raise the danger toast + error email. A company that simply had no
      # extract is NOT an error — its report was still generated with a "No data available" section.
      if @errors.any?
        msg = "Portfolio Report Generation completed with the following #{@errors.count} errors.
      <div>
      #{@errors.pluck(:msg).join('<br>')}</div>"
        send_notification("#{msg} #{document_location(final_document)}", user_id, "danger")
        EntityMailer.with(entity_id: portfolio_report.entity_id, user_id:, error_msg: @errors).doc_gen_errors.deliver_now
      else
        detail = if @companies_without_extracts.none?
                   ""
                 elsif generate_missing_extracts
                   "Extracts were generated for: #{@companies_without_extracts.join(', ')}."
                 else
                   "The following companies had no extract: #{@companies_without_extracts.join(', ')}."
                 end
        msg = ["Portfolio Report Generation completed.", detail, document_location(final_document)]
        send_notification(msg.compact_blank.join(" "), user_id, "success")
      end
    ensure
      FileUtils.rm_rf(run_dir) if run_dir
    end
  end

  # A "saved in <folder path>: <link>" fragment for the run's single output document, so the
  # completion toast tells the user both where the document landed and how to open it.
  # Returns "" when nothing was generated (every company errored out).
  #
  # @param document [Document, nil]
  # @return [String] An HTML fragment (user alerts are rendered html_safe).
  def document_location(document)
    return "" if document.blank?

    link = ActionController::Base.helpers.link_to(
      document.name, Rails.application.routes.url_helpers.document_path(document)
    )
    "Saved in #{folder_breadcrumb(document.folder)}: #{link}"
  end

  # "Portfolio Reports / Generated Portfolio Reports" — walks up from the document's folder, dropping the
  # root folder (named "/") so the path reads as the user sees it in the folder tree.
  def folder_breadcrumb(folder)
    names = []
    while folder
      names.unshift(folder.name)
      folder = folder.parent
    end
    names.compact_blank.reject { |name| name == "/" }.join(" / ")
  end

  # Finds the latest extract matching this portfolio company, report and date range, if any.
  #
  # @return [PortfolioReportExtract, nil]
  def find_latest_extract(portfolio_company, portfolio_report, start_date, end_date)
    PortfolioReportExtract.matching(portfolio_report.id, portfolio_company.id, start_date, end_date)
                          .order(created_at: :desc).first
  end

  private

  # The first part is the positional report/template; the rest come from additional_parts. Reports
  # are looked up inside the first report's entity so a tampered id from another entity is not found.
  #
  # @return [Array<Part>] In row order.
  def parts_for(portfolio_report, template_id, additional_parts)
    extra = Array(additional_parts).map do |part|
      part = part.to_h.stringify_keys
      Part.new(PortfolioReport.where(entity_id: portfolio_report.entity_id).find(part["portfolio_report_id"]), part["template_id"])
    end
    [Part.new(portfolio_report, template_id)] + extra
  end

  # The run's companies, entity scoped and A-Z, resolved once for every part.
  def resolve_companies(portfolio_report, portfolio_company_ids)
    portfolio_companies = portfolio_report.entity.investors.portfolio_companies
    if portfolio_company_ids.present?
      portfolio_companies = portfolio_companies.where(id: portfolio_company_ids)
    elsif portfolio_report.tags
      # Are we running this for specific tags?
      # The new bulk UI always passes explicit portfolio_company_ids (the user finalizes the
      # selection on screen), so this tag-based fallback only fires for callers that enqueue
      # the job without ids. Kept for backwards compatibility with that older invocation style.
      portfolio_report_tags = portfolio_report.tags.split(",").map(&:strip)
      portfolio_companies = portfolio_companies.select do |portfolio_company|
        portfolio_company.tag_list.split(',').map(&:strip).intersect?(portfolio_report_tags)
      end
    end
    # H6: a consistent alphabetical order so the combined document reads the same way every time
    portfolio_companies.to_a.sort_by { |company| company.investor_name.to_s.downcase }
  end

  # One document per company for a normal report. Companies whose piece fails are left out and recorded.
  #
  # @return [Array<Document>] In company order.
  def company_documents(part, portfolio_companies, start_date, end_date, user_id, generate_missing_extracts)
    portfolio_companies.flat_map do |portfolio_company|
      portfolio_report_extract = extract_for(portfolio_company, part.report, start_date, end_date, user_id, generate_missing_extracts)
      next [] unless portfolio_report_extract

      # Now generate the actual report using the template. Run synchronously (not perform_later)
      # so that, once every part is done, we can join the generated documents below. The silent
      # variant suppresses the doc gen job's own per-company toasts and error email so this job
      # can report the whole run once, below.
      doc_gen_job = PortfolioReportDocGenSilentJob.new(portfolio_report_extract.id, part.template_id, start_date, end_date, user_id)
      doc_gen_job.perform_now
      # X6: a company whose piece fails is recorded; the other pieces carry on
      @errors.concat(doc_gen_job.error_msg.map { |error| { msg: error[:msg], model: error[:model].to_s } })
      # generated_documents is nil when the doc gen job bailed out on invalid inputs.
      doc_gen_job.generated_documents.to_a
    end
  end

  # The extract a normal part's company piece is built from. E7: looked up once per report and
  # company, so two rows of the same report share it and the company is noted once.
  #
  # @return [PortfolioReportExtract, nil] nil when it could not be found or created (the error is recorded).
  def extract_for(portfolio_company, portfolio_report, start_date, end_date, user_id, generate_missing_extracts)
    key = [portfolio_report.id, portfolio_company.id]
    return @extracts[key] if @extracts.key?(key)

    portfolio_report_extract = find_latest_extract(portfolio_company, portfolio_report, start_date, end_date)
    if portfolio_report_extract.blank? || portfolio_report_extract.data.blank?
      @companies_without_extracts << portfolio_company.name unless @companies_without_extracts.include?(portfolio_company.name)
      portfolio_report_extract =
        if generate_missing_extracts
          # Generate missing extracts synchronously as we are already in a job. This calls
          # the per-company method rather than the job's bulk #perform so we get this
          # company's error back here, without firing the extract job's own batch summary.
          extract, msg = GeneratePortfolioReportExtractsJob.new.generate_extract(
            portfolio_company, portfolio_report, start_date, end_date, user_id
          )
          @errors << { msg: msg, model: portfolio_company.to_s } if msg.present?
          extract
        else
          # E5: never skip: generate the report anyway with an empty extract. The doc renders a
          # single "No data available" section the user can fill in.
          PortfolioReportExtract.create!(
            entity_id: portfolio_report.entity_id,
            portfolio_company_id: portfolio_company.id,
            portfolio_report_id: portfolio_report.id,
            start_date:, end_date:, data: nil, source_document_ids: []
          )
        end
    end
    @extracts[key] = portfolio_report_extract
  rescue StandardError => e
    msg = "Error generating extract for report #{portfolio_report}: #{e.message}"
    Rails.logger.error(msg)
    @errors << { msg: msg, model: portfolio_company.to_s }
    nil
  end

  # The .docx for a consolidated part, built once for all companies. Nothing is saved as a Document.
  #
  # @return [String, nil] Path of the file; nil when it failed (the error is recorded).
  def consolidated_file(part, portfolio_companies, output_dir, start_date, end_date, user_id)
    template = part.report.documents.find(part.template_id)
    FileUtils.mkdir_p(output_dir)
    PortfolioReportConsolidatedDocGenerator.new(portfolio_companies, template, start_date, end_date, user_id, output_dir:).call
  rescue StandardError => e
    template_name = template&.name || "template #{part.template_id}"
    msg = "Error generating #{ERB::Util.html_escape(template_name)} (consolidated): #{ERB::Util.html_escape(e.message)}"
    Rails.logger.error { "#{msg} (report #{part.report.id}, template #{part.template_id}, user #{user_id})" }
    @errors << { msg: msg, model: part.report.to_s }
    nil
  end

  # The one document the run ends with: the lone company's own document when there is exactly that,
  # otherwise the pieces joined. X8: nothing generated means no document.
  #
  # @return [Document, nil]
  def final_document(sources, first_part, portfolio_report, portfolio_companies, start_date, end_date, user_id)
    return nil if sources.empty?
    # E3: one company's piece on its own needs no combined file
    return sources.first if sources.size == 1 && sources.first.is_a?(Document)

    # Named and set up from the first row's template; the first piece's look wins in the file
    template = portfolio_report.entity.documents.find_by(id: first_part.template_id)
    PortfolioReportDocumentMerger.call(sources, portfolio_report:, template:, company_count: portfolio_companies.size,
                                                start_date:, end_date:, user_id:)
  rescue StandardError => e
    # X9: merge failure shouldn't lose the fact that every company's own report already
    # generated successfully — report it as an error and carry on without a combined document
    # so the completion notification still says what happened.
    msg = "Error merging portfolio report documents for report #{portfolio_report}: #{e.message}"
    Rails.logger.error(msg)
    @errors << { msg: msg, model: portfolio_report.to_s }
    nil
  end
end
