class AddDocumentFolderToApprovalResponse < ActiveRecord::Migration[7.1]
  def change
    add_reference :approval_responses, :document_folder, null: true, foreign_key: {to_table: :folders}
  end
end
