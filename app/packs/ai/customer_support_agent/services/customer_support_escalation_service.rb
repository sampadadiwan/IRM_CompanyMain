# frozen_string_literal: true

# Handles escalation from the Customer Support Agent to the human CS team.
# Creates an escalation record, locks the session, and notifies CS via email.
#
# @see EscalateToHumanTool
# @see CustomerSupportEscalation
class CustomerSupportEscalationService
  # @param session [AgentChatSession]
  # @param user [User]
  # @param entity [Entity]
  # @param reason [String]
  # @param summary [String]
  def self.escalate!(session:, user:, entity:, reason:, summary:)
    escalation = CustomerSupportEscalation.create!(
      agent_chat_session: session,
      user: user,
      entity: entity,
      reason: reason,
      summary: summary
    )

    session.update!(status: "escalated")

    CustomerSupportEscalationMailer.with(escalation_id: escalation.id).escalation_created.deliver_later

    escalation
  end
end
