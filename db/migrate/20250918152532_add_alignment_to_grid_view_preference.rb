class AddAlignmentToGridViewPreference < ActiveRecord::Migration[8.0]
  def change
    add_column :grid_view_preferences, :alignment, :string, limit: 10
  end
end
