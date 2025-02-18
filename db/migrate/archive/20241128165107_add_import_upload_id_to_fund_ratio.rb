class AddImportUploadIdToFundRatio < ActiveRecord::Migration[7.2]
  def change
    add_column :fund_ratios, :import_upload_id, :bigint
  end
end
