class AddLockedToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :lock_allocations, :boolean, default: false
  end
end
