class AddEnabledToSupportAgent < ActiveRecord::Migration[8.0]
  def change
    add_column :support_agents, :enabled, :boolean, default: true, null: false
  end
end
