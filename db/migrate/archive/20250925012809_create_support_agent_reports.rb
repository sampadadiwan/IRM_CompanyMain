class CreateSupportAgentReports < ActiveRecord::Migration[8.0]
  def change
    create_table :support_agent_reports do |t|
      t.references :owner, polymorphic: true, null: false
      t.string :owner_name, limit: 50
      t.references :support_agent, null: false, foreign_key: true
      t.string :support_agent_name, limit: 50
      t.json :json_fields

      t.timestamps
    end
  end
end
