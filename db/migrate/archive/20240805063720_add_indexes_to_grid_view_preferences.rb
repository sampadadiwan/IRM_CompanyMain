class AddIndexesToGridViewPreferences < ActiveRecord::Migration[7.1]
  def change
    add_index :grid_view_preferences, [:sequence]
  end
end
