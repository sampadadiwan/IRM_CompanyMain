class CreateCustomGridView < ActiveRecord::Migration[7.1]
  def change
    create_table :custom_grid_views do |t|
      t.bigint :owner_id, null: false
      t.string :owner_type, null: false

      t.timestamps
    end
  end
end
