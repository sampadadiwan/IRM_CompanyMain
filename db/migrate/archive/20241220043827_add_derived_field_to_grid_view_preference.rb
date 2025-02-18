class AddDerivedFieldToGridViewPreference < ActiveRecord::Migration[7.2]
  def change
    add_column :grid_view_preferences, :derived_field, :boolean
  end
end
