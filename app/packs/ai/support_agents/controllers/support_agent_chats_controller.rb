# frozen_string_literal: true

# Handles chat interactions for a SupportAgent via JSON API.
# Delegates to GenericChatAgent for message processing and
# persists conversations in AgentChatSession.
#
# @see GenericChatAgent
# @see AgentChatSession

class SupportAgentChatsController < ApplicationController
  LLM_CONNECTIVITY_ERROR_PATTERN = /
    failed\ to\ open\ tcp\ connection|
    getaddrinfo|
    temporary\ failure\ in\ name\ resolution|
    name\ or\ service\ not\ known|
    connection\ refused|
    connection\ reset|
    network\ is\ unreachable|
    timed\ out|
    execution\ expired
  /ix

  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def create
    @support_agent = SupportAgent.find(params[:support_agent_id])
    authorize @support_agent, :show?

    target = find_chattable

    result = GenericChatAgent.call(
      support_agent_id: @support_agent.id,
      target: target || @support_agent,
      user_message: params[:message],
      analyst_id: current_user.id
    )

    if result.success?
      session = result[:chat_session]
      ai_msg = session.agent_chat_messages.where(role: 'assistant').last
      render json: { success: true, response: result[:ai_response], message_id: ai_msg&.id, session_id: session.id }
    else
      render json: { success: false, error: "Chat agent execution failed" }, status: :unprocessable_entity
    end
  rescue StandardError => e
    if llm_connectivity_error?(e)
      Rails.logger.warn "[SupportAgentChatsController] LLM connectivity error: #{e.message}"
      render json: {
        success: false,
        error: "AI service is temporarily unreachable (network/DNS). Please try again shortly."
      }, status: :service_unavailable
    else
      Rails.logger.error "[SupportAgentChatsController] #{e.message}\n#{Array(e.backtrace).first(5).join("\n")}"
      render json: { success: false, error: "Chat error: #{e.message}" }, status: :internal_server_error
    end
  end

  def index
    @support_agent = SupportAgent.find(params[:support_agent_id])
    authorize @support_agent, :show?

    target = find_chattable

    session = AgentChatSession.find_by(
      chattable: target || @support_agent,
      support_agent: @support_agent,
      analyst_id: current_user.id
    )

    messages = if session
                 session.agent_chat_messages.order(:created_at).map do |m|
                   { id: m.id, role: m.role, content: m.content, created_at: m.created_at.iso8601 }
                 end
               else
                 []
               end

    render json: { success: true, session_id: session&.id, messages: messages }
  end

  def destroy
    @support_agent = SupportAgent.find(params[:support_agent_id])
    authorize @support_agent, :show?
    session = AgentChatSession.find_by!(id: params[:id], analyst_id: current_user.id)
    session.destroy!
    render json: { success: true }
  end

  private

  def find_chattable
    return nil unless params[:chattable_type].present? && params[:chattable_id].present?

    params[:chattable_type].constantize.find_by(id: params[:chattable_id])
  rescue NameError
    nil
  end

  def llm_connectivity_error?(error)
    each_error_cause(error).any? do |ex|
      ex.is_a?(SocketError) ||
        ex.is_a?(Timeout::Error) ||
        ex.is_a?(Errno::ECONNREFUSED) ||
        ex.is_a?(Errno::ECONNRESET) ||
        ex.is_a?(Errno::EHOSTUNREACH) ||
        ex.is_a?(Errno::ENETUNREACH) ||
        ex.message.to_s.match?(LLM_CONNECTIVITY_ERROR_PATTERN)
    end
  end

  def each_error_cause(error)
    causes = []
    current = error

    while current && causes.exclude?(current)
      causes << current
      current = current.cause
    end

    causes
  end
end
