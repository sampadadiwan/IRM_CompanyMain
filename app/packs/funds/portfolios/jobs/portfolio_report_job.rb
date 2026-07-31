class PortfolioReportJob < LlmReportJob
  queue_as :low

  # This job is called to generate a portfolio report for a given date range.
  # A report is ALWAYS generated for every company: when a company has no extract and
  # generate_missing_extracts is false, an empty extract is used and the report renders a
  # single "No data available" section. Pass generate_missing_extracts: true to instead call
  # the LLM to build an extract for companies that don't have one yet.
  def perform(portfolio_report_id, template_id, start_date, end_date, user_id, portfolio_company_ids: nil,
              generate_missing_extracts: false)
    Chewy.strategy(:sidekiq) do
      @errors = []
      portfolio_report = PortfolioReport.find(portfolio_report_id)

      # Get the portfolio_companies for the entity
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

      companies_without_extracts = []
      generated_documents = []
      portfolio_companies.each do |portfolio_company|
        portfolio_report_extract = nil
        begin
          portfolio_report_extract = find_latest_extract(portfolio_company, portfolio_report, start_date, end_date)
          if portfolio_report_extract.blank? || portfolio_report_extract.data.blank?
            companies_without_extracts << portfolio_company.name
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
                # Never skip: generate the report anyway with an empty extract. The doc renders a
                # single "No data available" section the user can fill in.
                PortfolioReportExtract.create!(
                  entity_id: portfolio_report.entity_id,
                  portfolio_company_id: portfolio_company.id,
                  portfolio_report_id: portfolio_report.id,
                  start_date:, end_date:, data: nil, source_document_ids: []
                )
              end
          end
        rescue StandardError => e
          msg = "Error generating extract for report #{portfolio_report}: #{e.message}"
          Rails.logger.error(msg)
          @errors << { msg: msg, model: portfolio_company.to_s }
          next
        end

        # Now generate the actual report using the template. Run synchronously (not perform_later)
        # so that, once every company in the batch is done, we can merge the generated documents
        # across companies below. The silent variant suppresses the doc gen job's own per-company
        # toasts and error email so this job can report the whole batch once, below.
        doc_gen_job = PortfolioReportDocGenSilentJob.new(portfolio_report_extract.id, template_id, start_date, end_date, user_id)
        doc_gen_job.perform_now
        # generated_documents is nil when the doc gen job bailed out on invalid inputs.
        generated_documents.concat(doc_gen_job.generated_documents.to_a)
        @errors.concat(doc_gen_job.error_msg.map { |error| { msg: error[:msg], model: error[:model].to_s } })
      end

      # All companies share a single output template, so the run always ends with exactly one
      # document of interest: the merged one when several companies were generated, otherwise
      # the single company's own document.
      final_document =
        if generated_documents.size > 1
          begin
            PortfolioReportDocumentMerger.call(generated_documents, portfolio_report:, start_date:, end_date:, user_id:)
          rescue StandardError => e
            # Merge failure shouldn't lose the fact that every company's own report already
            # generated successfully — report it as an error and fall back to the first
            # individual document so the completion notification still links somewhere useful.
            msg = "Error merging portfolio report documents for report #{portfolio_report}: #{e.message}"
            Rails.logger.error(msg)
            @errors << { msg: msg, model: portfolio_report.to_s }
            nil
          end
        else
          generated_documents.first
        end

      # Only genuine failures raise the danger toast + error email. A company that simply had no
      # extract is NOT an error — its report was still generated with a "No data available" section.
      if @errors.any?
        msg = "Portfolio Report Generation completed with the following #{@errors.count} errors.
      <div>
      #{@errors.pluck(:msg).join('<br>')}</div>"
        send_notification("#{msg} #{document_location(final_document)}", user_id, "danger")
        EntityMailer.with(entity_id: portfolio_report.entity_id, user_id:, error_msg: @errors).doc_gen_errors.deliver_now
      else
        detail = if companies_without_extracts.none?
                   ""
                 elsif generate_missing_extracts
                   "Extracts were generated for: #{companies_without_extracts.join(', ')}."
                 else
                   "The following companies had no extract: #{companies_without_extracts.join(', ')}."
                 end
        msg = ["Portfolio Report Generation completed.", detail, document_location(final_document)]
        send_notification(msg.compact_blank.join(" "), user_id, "success")
      end
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

  # "Investors / Generated Portfolio Reports" — walks up from the document's folder, dropping the
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
end
