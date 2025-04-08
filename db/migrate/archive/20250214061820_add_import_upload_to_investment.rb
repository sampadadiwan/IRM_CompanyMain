class AddImportUploadToInvestment < ActiveRecord::Migration[7.2]
  def change
    add_column :investments, :import_upload_id, :integer, null: true    
  end
end
