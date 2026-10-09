class ImportKpiWorkbookJob < ApplicationJob
  queue_as :low

  def perform(kpi_report_id, user_id, update_existing_kpis: true)
    Chewy.strategy(:sidekiq) do
      run_import(kpi_report_id, user_id, update_existing_kpis)
    end
  rescue StandardError => e
    # A portco submission must never stay "submitted / import pending" forever: reopen it so the portco
    # can resubmit and the fund can see what happened, then let the error surface as usual.
    report = KpiReport.find_by(id: kpi_report_id)
    report.reopen_after_failed_import! if report&.import_status == 'pending'
    raise e
  end

  private

  def run_import(kpi_report_id, user_id, update_existing_kpis)
    kpi_report = KpiReport.find(kpi_report_id)
    # The workbook which contains the kpis to be imported
    kpi_file = kpi_report.documents.where(name: "KPIs").first

    user = User.find(user_id)

    # The portfolio company for which the kpi report is created
    portfolio_company = kpi_report.portfolio_company
    # The mappings used to identify the kpis to be extracted, ensure they are not 'compute' type
    kpi_mappings = portfolio_company.investor_kpi_mappings.not_compute
    # target_kpis = kpi_mappings.pluck(:reported_kpi_name)

    # Extract and save the kpis from the workbook
    @kpi_reader = KpiWorkbookReader.new(kpi_report, kpi_file, kpi_mappings, user, portfolio_company, update_existing_kpis:)
    @kpi_reader.extract_kpis

    # Persist the structured verdict on the report so the fund's page and the portco's panel show
    # the outcome of the actual import (same shape as the pre-save KpiWorkbookReader#validate result).
    # 'document_id' lets the edit page trust this verdict for the attached document (see _xlsx_preview).
    kpi_report.update_columns(validation_result: @kpi_reader.result.merge('source' => 'import', 'document_id' => kpi_file&.id), validated_at: Time.current)

    if @kpi_reader.error_msg.present?
      # error_msg carries blocking errors plus the legacy-emailed warnings (missing KPIs etc.);
      # the toast severity reflects whether anything actually blocked.
      msg = @kpi_reader.errors? ? "Errors in extracting KPIs from the workbook for #{kpi_report.as_of}." : "KPIs imported for #{kpi_report.as_of} with warnings."
      send_notification("#{msg} Details sent via email.", user.id, @kpi_reader.errors? ? :error : :warning)
      # Clean and prepare for JSON-safe mailer transfer
      safe_report_data = @kpi_reader.error_msg.map do |err|
        err.transform_values do |v|
          case v
          when ActiveRecord::Base
            v.respond_to?(:name) ? v.name : v.id.to_s
          else
            v.to_s
          end
        end.merge('status' => err[:severity].to_s.presence || 'error')
      end

      EntityMailer.with(
        entity_id: user.entity_id,
        user_id: user.id,
        report_data: safe_report_data.to_json, # Convert to JSON string
        subject: msg
      ).send_report.deliver_now
    end

    # Kick off the percentage change job synchronously. extract_kpis above already ran cumulation
    # (KpiCumulateJob.perform_now inside KpiWorkbookReader), so running this inline right after
    # guarantees percentages cover the cumulated Quarter/YTD/Year KPIs too. Queuing it instead
    # gave no ordering guarantee and imported KPIs could briefly show missing MoM/YoY changes.
    # We're already in a background job, so there's no latency benefit to enqueuing another one.
    KpiPercentageChangeJob.perform_now(portfolio_company.id, user.id)

    # Portco submission lifecycle (§2.2 E): the controller flips the report to `submitted` with
    # import_status `pending`; the fund hears about it only here, once the data is actually staged.
    # A post-gate failure reopens the report for the portco and tells the fund why.
    if kpi_report.reload.import_status == 'pending'
      if @kpi_reader.errors?
        kpi_report.reopen_after_failed_import!
      else
        kpi_report.update_columns(import_status: 'imported')
        kpi_report.notify_fund_of_submission! if kpi_report.status_submitted?
      end
    end

    # The KPI report journey (kpi-report-journey). The report the workbook was uploaded on is a request,
    # so it gets a journey if it hasn't one — never the reports this import created for other periods.
    # Then every open journey of the portfolio company moves on: the staged KPIs are counted portco-wide.
    # (This replaces launching a workflow on the portfolio company itself — design Decision 10.)
    # Worked examples H3, H9, E14 — openspec/changes/kpi-report-journey/design.md#worked-examples
    kpi_report.start_journey!(user) unless @kpi_reader.errors?
    KpiReport.journey_progress_for_portco(kpi_report.entity_id, kpi_report.portfolio_company_id, actor: user)
  end
end
