class AddCmfAllocationToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :cmf_allocation_percentage, :text
  end
end
