class UpdateGridViewPreferencesAssociation < ActiveRecord::Migration[7.1]
  def change
    add_reference :grid_view_preferences, :owner, polymorphic: true, null: false
    add_index :grid_view_preferences, [:owner_id, :owner_type]
    
    add_reference :grid_view_preferences, :entity, null: true, foreign_key: true

    GridViewPreference.find_each do |preference|
      preference.update(owner_id: preference.custom_grid_view.owner_id, owner_type: 'FormType', entity_id: preference.custom_grid_view.owner.entity_id)
    end
  end
end
