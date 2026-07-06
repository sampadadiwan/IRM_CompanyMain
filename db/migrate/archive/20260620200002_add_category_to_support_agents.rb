class AddCategoryToSupportAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :support_agents, :category, :string
  end
end
