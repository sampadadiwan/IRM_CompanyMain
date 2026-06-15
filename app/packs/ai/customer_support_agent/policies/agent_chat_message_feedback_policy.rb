# frozen_string_literal: true

# Authorizes feedback actions on agent chat messages.
# FM users can only rate messages from their own chat sessions.
#
# @see AgentChatMessageFeedback
# @see SupportAgentChatFeedbacksController
class AgentChatMessageFeedbackPolicy < ApplicationPolicy
  # @return [Boolean] true if the message belongs to the current user's session
  def update?
    record.agent_chat_message.agent_chat_session.analyst_id == user.id
  end
end
