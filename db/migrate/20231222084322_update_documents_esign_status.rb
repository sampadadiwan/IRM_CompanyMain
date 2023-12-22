class UpdateDocumentsEsignStatus < ActiveRecord::Migration[7.1]
  # change esign status default to ""
  def change
    Document.with_deleted.where(esign_status: nil).update_all(esign_status: "")
    change_column :documents, :esign_status, :string, null: false, default: ""
  end
end
