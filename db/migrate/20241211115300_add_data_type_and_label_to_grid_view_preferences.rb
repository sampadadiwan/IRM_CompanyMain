class AddDataTypeAndLabelToGridViewPreferences < ActiveRecord::Migration[7.2]
  def change
    add_column :grid_view_preferences, :data_type, :string
    add_column :grid_view_preferences, :label, :string
  end
end
