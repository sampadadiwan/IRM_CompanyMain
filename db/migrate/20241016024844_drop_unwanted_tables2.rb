class DropUnwantedTables2 < ActiveRecord::Migration[7.1]
  def change
    drop_table :activities
    drop_table :adhaar_esigns
    drop_table :esigns
    drop_table :caphive_agents
    drop_table :document_chats
    drop_table :emailbutler_messages
    drop_table :impressions
    drop_table :signature_workflows
  end
end
