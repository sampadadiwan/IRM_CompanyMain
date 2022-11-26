class AddEntityTypeToEntity < ActiveRecord::Migration[7.0]
  def change
    change_column :entities, :entity_type, :string, limit: 25
  end
end
