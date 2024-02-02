class AddInvestorToKpi < ActiveRecord::Migration[7.1]
  def change
    add_reference :kpis, :portfolio_company, null: true, foreign_key: {to_table: :investors}
    add_reference :kpi_reports, :portfolio_company, null: true, foreign_key: {to_table: :investors}
  end
end
