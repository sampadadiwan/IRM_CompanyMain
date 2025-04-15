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
      KpiWorkbookReader.new(kpi_file, target_kpis, user, portfolio_company).extract_kpis
    end
  end
end
