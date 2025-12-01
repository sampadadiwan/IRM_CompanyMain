class AddSupportAgentsToEntity < ActiveRecord::Migration[8.0]
  def change
    add_column :entities, :support_agents, :integer, default: 0, null: false
  end
end
