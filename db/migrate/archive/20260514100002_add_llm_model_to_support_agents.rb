class AddLlmModelToSupportAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :support_agents, :llm_model, :string
  end
end
