# frozen_string_literal: true

# Handles user feedback (thumbs up/down + optional notes) on agent chat messages.
# Upserts into AgentChatMessageFeedback — the same row that LLM-as-judge (Module 6)
# will later write scores into.
#
# @see AgentChatMessageFeedback
# @see AgentChatMessageFeedbackPolicy
class SupportAgentChatFeedbacksController < ApplicationController
  # @route PATCH /support_agents/:support_agent_id/chats/:id/feedback
  #
  # @param rating [String] "positive" or "negative"
  # @param notes [String] optional free-text note (typically on negative feedback)
  # @return [JSON] { success: true, feedback_id: Integer }
  def update
    @support_agent = SupportAgent.find(params[:support_agent_id])
    @message = AgentChatMessage.joins(:agent_chat_session)
                               .where(agent_chat_sessions: {
                                        support_agent_id: @support_agent.id,
                                        analyst_id: current_user.id
                                      })
                               .find(params[:id])

    @feedback = AgentChatMessageFeedback.find_or_initialize_by(
      agent_chat_message: @message
    )
    @feedback.assign_attributes(
      user: current_user,
      entity: @support_agent.entity,
      channel: @message.channel || "web",
      status: @feedback.new_record? ? "open" : @feedback.status
    )
    @feedback.rating = params[:rating] if params.key?(:rating)
    @feedback.notes = params[:notes] if params.key?(:notes)

    authorize @feedback

    if @feedback.save
      render json: { success: true, feedback_id: @feedback.id }
    else
      render json: { success: false, errors: @feedback.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
