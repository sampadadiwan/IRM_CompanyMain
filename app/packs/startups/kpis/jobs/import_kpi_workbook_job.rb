class ImportKpiWorkbookJob < ApplicationJob
  queue_as :low

  def perform(kpi_report_id, user_id)
    Chewy.strategy(:sidekiq) do
      kpi_report = KpiReport.find(kpi_report_id)
      # The workbook which contains the kpis to be imported
      kpi_file = kpi_report.documents.where(name: "KPIs").first

      kpi_report.entity
      user = User.find(user_id)

      # The portfolio company for which the kpi report is created
      portfolio_company = kpi_report.portfolio_company
      # The mappings used to identify the kpis to be extracted
      kpi_mappings = portfolio_company.investor_kpi_mappings
      target_kpis = kpi_mappings.pluck(:reported_kpi_name)

      # Extract and save the kpis from the workbook
      @kpi_reader = KpiWorkbookReader.new(kpi_file, target_kpis, user, portfolio_company)
      @kpi_reader.extract_kpis

      if @kpi_reader.error_msg.present?
        msg = "Errors in extracting KPIs from the workbook for #{kpi_report.as_of}."
        send_notification("#{msg} Errors sent via email.", user.id, :error)
        EntityMailer.with(entity_id: user.entity_id, user_id: user.id, error_msg: @kpi_reader.error_msg, subject: msg).doc_gen_errors.deliver_now
      end

      # Kick of percentage change job
      KpiPercentageChangeJob.perform_later(portfolio_company.entity_id, user.id)
    end
  end
end
