class AddPriceToAllocation < ActiveRecord::Migration[7.1]
  def change
    add_column :allocations, :price, :decimal, precision: 20, scale: 2, default: 0
  end
end
