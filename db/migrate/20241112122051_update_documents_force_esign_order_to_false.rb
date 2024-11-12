class UpdateDocumentsForceEsignOrderToFalse < ActiveRecord::Migration[7.1]
  def change
    change_column_default :documents, :force_esign_order, from: true, to: false
  end
end
