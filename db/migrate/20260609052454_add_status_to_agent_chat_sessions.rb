# frozen_string_literal: true

# Adds status column to agent_chat_sessions for escalation flow tracking.
class AddStatusToAgentChatSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_chat_sessions, :status, :string, limit: 20, default: "active", null: false
    add_index :agent_chat_sessions, :status
  end
end
