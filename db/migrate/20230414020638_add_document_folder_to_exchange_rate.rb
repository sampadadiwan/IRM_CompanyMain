class AddDocumentFolderToExchangeRate < ActiveRecord::Migration[7.0]
  def change
    add_reference :exchange_rates, :document_folder, null: true, foreign_key: {to_table: :folders}
  end
end
