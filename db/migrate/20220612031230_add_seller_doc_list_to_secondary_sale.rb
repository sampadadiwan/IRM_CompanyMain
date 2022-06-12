class AddSellerDocListToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :seller_doc_list, :text
    add_column :secondary_sales, :seller_transaction_fees_pct, :decimal, precision: 5, scale: 2
  end
end
