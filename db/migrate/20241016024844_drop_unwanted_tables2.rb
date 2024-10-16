class DropUnwantedTables2 < ActiveRecord::Migration[7.1]
  def change
    drop_table :activities, if_exists: true
    drop_table :adhaar_esigns, if_exists: true
    drop_table :esigns, if_exists: true
    drop_table :caphive_agents, if_exists: true
    drop_table :document_chats, if_exists: true
    drop_table :emailbutler_messages, if_exists: true
    drop_table :impressions, if_exists: true
    drop_table :signature_workflows, if_exists: true
  end
end
