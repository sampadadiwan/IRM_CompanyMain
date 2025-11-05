class AddStatusToSupportAgentReport < ActiveRecord::Migration[8.0]
  def change
    add_column :support_agent_reports, :status, :string, limit: 10, default: "pending", null: false
  end
end
