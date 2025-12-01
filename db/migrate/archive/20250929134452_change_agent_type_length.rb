class ChangeAgentTypeLength < ActiveRecord::Migration[8.0]
  def change
    change_column :support_agents, :agent_type, :string, limit: 30
  end
end
