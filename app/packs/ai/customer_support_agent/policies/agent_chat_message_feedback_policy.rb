# frozen_string_literal: true

# Authorizes feedback actions on agent chat messages.
# FM users can only rate messages from their own chat sessions.
#
# @see AgentChatMessageFeedback
# @see SupportAgentChatFeedbacksController
class AgentChatMessageFeedbackPolicy < ApplicationPolicy
  # @return [Boolean] true if the message belongs to the current user's session
  def update?
    support? || record.agent_chat_message.agent_chat_session.analyst_id == user.id
  end

  # Support users can view feedback for their mapped entities
  def show?
    support? || record.agent_chat_message.agent_chat_session.analyst_id == user.id
  end

  # Support users can re-test feedback items
  def retest?
    support?
  end

  class Scope < ApplicationPolicy::Scope
    # @return [ActiveRecord::Relation] feedbacks scoped to support user's mapped entities, or user's own entity
    def resolve
      if user.support?
        mapped_entity_ids = SupportClientMapping.where(user: user, enabled: true).pluck(:entity_id)
        scope.where(entity_id: mapped_entity_ids)
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end
end
