class AddSignFlagsToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :buyer_signature_types, :integer, default: 0
    add_column :secondary_sales, :seller_signature_types, :integer, default: 0
  end
end
