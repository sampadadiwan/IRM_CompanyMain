# frozen_string_literal: true

# Adds WhatsApp channel and session-state columns to agent_chat_sessions.
# - channel: distinguishes web sessions from whatsapp sessions
# - wa_state: tracks the WhatsApp conversation state machine
# - wa_metadata: stores per-session WhatsApp state (agent/fund menus, selections, feedback flags)
class AddWhatsappFieldsToAgentChatSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_chat_sessions, :channel, :string, limit: 20, default: "web", null: false unless column_exists?(:agent_chat_sessions, :channel)
    add_column :agent_chat_sessions, :wa_state, :string, limit: 30 unless column_exists?(:agent_chat_sessions, :wa_state)
    add_column :agent_chat_sessions, :wa_metadata, :json unless column_exists?(:agent_chat_sessions, :wa_metadata)
    add_index :agent_chat_sessions, :channel unless index_exists?(:agent_chat_sessions, :channel)
  end
end
