class AddFormTypeToInvestorKpiMapping < ActiveRecord::Migration[8.0]
  def change
    add_reference :investor_kpi_mappings, :form_type, null: true, foreign_key: true
    add_column :investor_kpi_mappings, :json_fields, :json
    add_column :kpis, :rag_status, :json, null: true
  end
end
