class AddKpiForPeriodToAgentChart < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_charts, :kpi_before, :integer, default: 12
    add_column :agent_charts, :kpi_before_period, :string, limit: 10, default: 'Months'
  end
end
