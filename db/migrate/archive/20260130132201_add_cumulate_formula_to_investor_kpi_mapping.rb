class AddCumulateFormulaToInvestorKpiMapping < ActiveRecord::Migration[8.1]
  def change
    add_column :investor_kpi_mappings, :cumulate_formula, :string
  end
end
