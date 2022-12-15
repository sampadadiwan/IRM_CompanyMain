class ChangeBuyerSignatureInSecondarySale < ActiveRecord::Migration[7.0]
  def change
    change_column :secondary_sales, :buyer_signature_types, :string, limit: 20, default: ""
    change_column :secondary_sales, :seller_signature_types, :string, limit: 20, default: ""
  end
end
