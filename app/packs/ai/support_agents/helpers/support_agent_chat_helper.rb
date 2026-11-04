# frozen_string_literal: true

# View helpers for the floating agent chat window (support_agents/_chat_panel, _chat_window).
module SupportAgentChatHelper
  # The window's Turbo Frame id — one window per agent on a page.
  #
  # @param support_agent [SupportAgent]
  # @return [String]
  def agent_chat_frame_id(support_agent)
    "agent-chat-#{support_agent.id}"
  end

  # The window's own URL for a record, with extra params (session_id, new_session).
  #
  # @param support_agent [SupportAgent]
  # @param chattable [ActiveRecord::Base] the record the window is about
  # @return [String]
  def agent_chat_url(support_agent, chattable, **params)
    support_agent_chats_path(support_agent, chattable_type: chattable.class.name, chattable_id: chattable.id, **params)
  end
end
