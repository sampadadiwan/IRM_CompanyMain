class AddDocumentFolderToKpiReport < ActiveRecord::Migration[7.0]
  def change
    add_reference :kpi_reports, :document_folder, null: true, foreign_key: {to_table: :folders}
  end
end
