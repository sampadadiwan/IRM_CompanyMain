class MoveKpiReportsFromFund < ActiveRecord::Migration[7.1]
  def change
    KpiReport.where.not(portfolio_company_id: nil).joins(:portfolio_company).each do |kpi_report|
      kpi_report.update(entity_id: kpi_report.portfolio_company.entity_id)
    end
  end
end
