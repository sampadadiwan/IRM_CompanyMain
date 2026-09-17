# frozen_string_literal: true

# Chatbot misses (headless: `authorize :guide_search_miss`). Misses contain customer questions,
# so support users see only entities mapped to them, as on the CS Feedback Review dashboard.
class GuideSearchMissPolicy < GuideFaqsStaffPolicy
  # @param messages [ActiveRecord::Relation<AgentChatMessage>]
  # @return [ActiveRecord::Relation<AgentChatMessage>] restricted to entities the user may see
  def scope_messages(messages)
    return messages.none unless staff?
    return messages if user.has_cached_role?(:super)

    entity_ids = SupportClientMapping.where(user: user, enabled: true).select(:entity_id)
    messages.joins(agent_chat_session: :support_agent).where(support_agents: { entity_id: entity_ids })
  end
end
