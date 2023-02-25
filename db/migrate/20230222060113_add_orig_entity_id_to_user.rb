class AddOrigEntityIdToUser < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :advisor_entity_id, :bigint
    add_column :users, :investor_advisor_id, :bigint
  end
end
