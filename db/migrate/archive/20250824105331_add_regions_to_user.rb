class AddRegionsToUser < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :regions, :string, null: false, default: "in"
    add_column :users, :primary_region, :string, null: false, default: "in"
  end
end
