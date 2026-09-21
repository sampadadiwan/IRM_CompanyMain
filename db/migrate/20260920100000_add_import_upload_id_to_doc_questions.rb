class AddImportUploadIdToDocQuestions < ActiveRecord::Migration[8.0]
  def change
    add_column :doc_questions, :import_upload_id, :integer, null: true
  end
end
