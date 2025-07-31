class AddCommonSizeToInvestorKpiMapping < ActiveRecord::Migration[8.0]
  def change
    add_column :investor_kpi_mappings, :base_for_common_size, :boolean, default: false, null: false
    add_column :kpis, :common_size_value, :decimal, precision: 6, scale: 2, default: 0.0
  end
end
