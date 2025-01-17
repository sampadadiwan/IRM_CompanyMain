class AddDocumentFolderIdToAmlReports < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:aml_reports, :document_folder_id)
    add_reference :aml_reports, :document_folder, null: true, foreign_key: {to_table: :folders}
    end
  end
end
