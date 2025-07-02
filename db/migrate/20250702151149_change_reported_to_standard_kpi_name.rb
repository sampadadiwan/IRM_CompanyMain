class ChangeReportedToStandardKpiName < ActiveRecord::Migration[8.0]
  def change
    Kpi.all.each do |kpi|
      if kpi.portfolio_company
        mapping = kpi.portfolio_company.investor_kpi_mappings.where(reported_kpi_name: kpi.name).first
        kpi.update(name: mapping.standard_kpi_name) if mapping
      end
    end
  end
end
