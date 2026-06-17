# frozen_string_literal: true

# Hands the conversation off to the Caphive CS team. Creates an escalation record,
# locks the session, and triggers email notification. The agent should call this when
# it cannot answer confidently, the user explicitly asks for a human, or the issue
# is too complex.
#
# @see CustomerSupportEscalationService
# @see CustomerSupportEscalation
class EscalateToHumanTool < RubyLLM::Tool
  description "Escalate the conversation to the Caphive support team. Use when: " \
              "(1) you cannot answer the question confidently, " \
              "(2) the user explicitly asks to speak to a human, or " \
              "(3) the issue requires manual intervention. " \
              "Provide a clear reason and a summary of the conversation so far."

  param :reason,
        type: :string,
        desc: 'One of: customer_requested, low_confidence, complex_issue',
        required: true

  param :summary,
        type: :string,
        desc: 'Brief summary of the conversation and why escalation is needed',
        required: true

  # @param session [AgentChatSession] the current chat session
  # @param user [User] the FM user chatting
  # @param entity [Entity] the FM entity
  def initialize(session:, user:, entity:)
    super()
    @session = session
    @user = user
    @entity = entity
  end

  # @param reason [String] escalation reason
  # @param summary [String] conversation summary
  # @return [String] confirmation message shown to the user
  def execute(reason:, summary:)
    return "Invalid reason '#{reason}'. Must be one of: #{CustomerSupportEscalation::REASONS.join(', ')}" unless CustomerSupportEscalation::REASONS.include?(reason)

    return "This conversation has already been escalated. The support team has been notified." if @session.escalated?

    ::CustomerSupportEscalationService.escalate!(
      session: @session,
      user: @user,
      entity: @entity,
      reason: reason,
      summary: summary
    )

    "I've connected you with the Caphive support team. They'll review your conversation " \
      "and get back to you shortly. You'll receive a response via the platform."
  end
end
