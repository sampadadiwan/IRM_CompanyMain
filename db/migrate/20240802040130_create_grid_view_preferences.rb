class CreateGridViewPreferences < ActiveRecord::Migration[7.1]
  def change
    create_table :grid_view_preferences do |t|
      t.references :custom_grid_view, null: false, foreign_key: true
      t.string :name
      t.string :key
      t.boolean :selected
      t.integer :sequence

      t.timestamps
    end
  end
end
