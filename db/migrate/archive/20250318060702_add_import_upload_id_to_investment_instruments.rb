class AddImportUploadIdToInvestmentInstruments < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:investment_instruments, :import_upload_id)
      add_column :investment_instruments, :import_upload_id, :bigint
    end
  end
end
