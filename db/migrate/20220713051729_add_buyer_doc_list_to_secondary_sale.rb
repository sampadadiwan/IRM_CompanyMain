class AddBuyerDocListToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :buyer_doc_list, :text
  end
end
