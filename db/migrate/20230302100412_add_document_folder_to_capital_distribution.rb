class AddDocumentFolderToCapitalDistribution < ActiveRecord::Migration[7.0]
  def change
    add_reference :capital_distributions, :document_folder, null: true, foreign_key: {to_table: :folders}
    add_reference :capital_distribution_payments, :document_folder, null: true, foreign_key: {to_table: :folders}
  end
end
