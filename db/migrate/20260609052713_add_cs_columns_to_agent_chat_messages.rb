# frozen_string_literal: true

# Adds channel, tool_calls_summary, and guide_search_hit columns for Customer Support Agent tracking.
class AddCsColumnsToAgentChatMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_chat_messages, :channel, :string, limit: 20, default: "web", null: false
    add_column :agent_chat_messages, :tool_calls_summary, :json, null: true
    add_column :agent_chat_messages, :guide_search_hit, :boolean, default: false, null: false
  end
end
