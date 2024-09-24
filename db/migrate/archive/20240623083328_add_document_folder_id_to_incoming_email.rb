class AddDocumentFolderIdToIncomingEmail < ActiveRecord::Migration[7.1]
  def change
    add_reference :incoming_emails, :document_folder, null: true, foreign_key: {to_table: :folders}
  end
end
