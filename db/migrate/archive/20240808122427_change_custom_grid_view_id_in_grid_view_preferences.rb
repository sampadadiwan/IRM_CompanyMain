class ChangeCustomGridViewIdInGridViewPreferences < ActiveRecord::Migration[7.1]
  def change
    change_column_null :grid_view_preferences, :custom_grid_view_id, true
  end
end
