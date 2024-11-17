class AddForceEsignOrderToDocuments < ActiveRecord::Migration[7.1]
  def change
    add_column :documents, :force_esign_order, :boolean, default: true
  end
end
