class AddWithStepsToSupportAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :support_agents, :with_steps, :boolean, default: false
  end
end
