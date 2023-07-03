class RemoveSigningFieldsFromDocument < ActiveRecord::Migration[7.0]
  def change
    remove_column :documents, :signed_by_id
    remove_column :documents, :signed_by_accept
    remove_column :documents, :adhaar_esign_enabled
    remove_column :documents, :adhaar_esign_completed
    remove_column :documents, :signature_type
    remove_column :funds, :fund_signature_types
    remove_column :funds, :investor_signature_type
    remove_column :capital_commitments, :investor_signature_type
    remove_column :secondary_sales, :buyer_signature_types
    remove_column :interests, :buyer_signature_types
    remove_column :secondary_sales, :seller_signature_types
    remove_column :offers, :seller_signature_types
  end
end
