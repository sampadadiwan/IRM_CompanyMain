class AddDeletedAtToAllocation < ActiveRecord::Migration[7.1]
  def change
    add_column :allocations, :deleted_at, :timestamp
    add_index :allocations, :deleted_at
  end
end
