class AddProviderDocIdToDocuments < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :provider_doc_id, :string
  end
end
