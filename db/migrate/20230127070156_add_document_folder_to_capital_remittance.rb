class AddDocumentFolderToCapitalRemittance < ActiveRecord::Migration[7.0]
  def change
    add_reference :capital_remittances, :document_folder, null: true, foreign_key: {to_table: :folders}    
  end
end
