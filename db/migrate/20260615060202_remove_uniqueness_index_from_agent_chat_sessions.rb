# frozen_string_literal: true

# Removes the unique constraint on agent_chat_sessions that enforced one session
# per user per agent. With threaded sessions (session auto-expire after 30 min idle),
# users can have multiple sessions for the same agent.
class RemoveUniquenessIndexFromAgentChatSessions < ActiveRecord::Migration[7.0]
  def change
    remove_index :agent_chat_sessions, name: "index_agent_chat_sessions_uniqueness"
    add_index :agent_chat_sessions, %i[support_agent_id chattable_type chattable_id analyst_id],
              name: "index_agent_chat_sessions_lookup"
  end
end
