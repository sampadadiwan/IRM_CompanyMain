class AddImportUploadIdToDealInvestors < ActiveRecord::Migration[7.2]
  def change
    add_column :deal_investors, :import_upload_id, :bigint
    add_index :deal_investors, :import_upload_id
  end
end
