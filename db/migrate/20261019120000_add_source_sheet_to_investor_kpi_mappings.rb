# G27 (client onboarding): a KPI mapping can be limited to one sheet. Butterfly's P&L "Rent" and
# "Others" are also rows of its cash-flow statement, so without a scope the cash-flow upload stored
# cash paid as the P&L lines. Blank = every sheet, as before.
class AddSourceSheetToInvestorKpiMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :investor_kpi_mappings, :source_sheet, :string, limit: 100
  end
end
