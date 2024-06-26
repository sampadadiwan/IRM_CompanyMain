class AddDocumentFolderToCustomNotifications < ActiveRecord::Migration[7.1]
  def change
    add_reference :custom_notifications, :document_folder, null: true, foreign_key: {to_table: :folders}
  end
end
