class AddIndicativeToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :indicative_quantity, :bigint, default: 0
    add_column :secondary_sales, :show_quantity, :string, limit: 10
  end
end
