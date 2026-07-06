class FixAgentChartKpiBeforePeriodDefault < ActiveRecord::Migration[8.0]
  # KpiReport::PERIODS only has singular values ("Month", "Quarter", "Half Year",
  # "Year", "YTD") — the "Months" default meant AgentChart#get_kpis could never
  # match any KpiReport, so generated charts always had no data.
  def up
    change_column_default :agent_charts, :kpi_before_period, from: "Months", to: "Month"
    AgentChart.where(kpi_before_period: "Months").update_all(kpi_before_period: "Month")
  end

  def down
    change_column_default :agent_charts, :kpi_before_period, from: "Month", to: "Months"
  end
end
