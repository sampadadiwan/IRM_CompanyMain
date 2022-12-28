class AddParanoiaToOptionPool < ActiveRecord::Migration[7.0]
  def change
    add_column :option_pools, :deleted_at, :datetime
    add_index :option_pools, :deleted_at
    add_column :holdings, :deleted_at, :datetime
    add_index :holdings, :deleted_at
    add_column :excercises, :deleted_at, :datetime
    add_index :excercises, :deleted_at
  end
end
