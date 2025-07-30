class AddImportUploadIdToInvestorKpiMappings < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:investor_kpi_mappings, :import_upload_id)
      add_column :investor_kpi_mappings, :import_upload_id, :bigint, null: true
    end
  end
end
