# frozen_string_literal: true

# The floating agent chat window (support_agents/_chat_panel) on the chat kit: the window's thread and
# conversation list as HTML, and a question answered with a Turbo Stream. Delegates to
# GenericChatAgent and persists conversations in AgentChatSession.
#
# @see GenericChatAgent
# @see AgentChatSession
# @see openspec/changes/ai-chat-kit/design.md (card ⑦ Screen back ends)

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

  # X1 — what a failed answer says when the AI service cannot be reached.
  UNREACHABLE = "AI service is temporarily unreachable (network/DNS). Please try again shortly."

  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  # POST /support_agents/:support_agent_id/chats — a question in the window. On success the window is
  # re-rendered for the conversation it went into (its list included); on failure the pending answer
  # reads "Not answered" with the reason and the question goes back in the box (X1, X2).
  def create
    # Outside the rescue below: a missing agent or a refusal is handled like anywhere else (404 / Pundit).
    load_window
    message = params[:message].to_s.strip
    # E4 — a blank question is never sent (the box blocks it too).
    return head(:unprocessable_entity) if message.blank?

    ask_agent(message)
  end

  # GET /support_agents/:support_agent_id/chats — the window's inside: a conversation (the one asked
  # for, else the latest; none with new_session) and the record's conversation list.
  def index
    load_window
    @session = if params[:new_session].present? then nil
               elsif params[:session_id].present? then window_sessions.find_by(id: params[:session_id])
               else current_window_session
               end
    render partial: "support_agents/chat_window", locals: window_locals
  end

  def destroy
    @support_agent = SupportAgent.find(params[:support_agent_id])
    authorize @support_agent, :show?
    session = AgentChatSession.find_by!(id: params[:id], analyst_id: current_user.id)
    session.destroy!
    head :no_content
  end

  private

  # Asks GenericChatAgent and renders the window, or the failed answer (X1, X2).
  #
  # @param message [String]
  def ask_agent(message)
    result = GenericChatAgent.call(
      support_agent_id: @support_agent.id,
      target: @target,
      user_message: message,
      analyst_id: current_user.id,
      # E9, E10 — the conversation the window shows (decision 6); GenericChatAgent checks it is ours.
      session_id: params[:session_id].presence,
      new_session: ActiveModel::Type::Boolean.new.cast(params[:new_session])
    )

    if result.success?
      @session = result[:chat_session]
      render_window_stream
    else
      render_failed_answer("Chat agent execution failed", message, status: :unprocessable_entity)
    end
  rescue StandardError => e
    if llm_connectivity_error?(e)
      Rails.logger.warn "[SupportAgentChatsController] LLM connectivity error: #{e.message}"
      render_failed_answer(UNREACHABLE, message, status: :service_unavailable)
    else
      Rails.logger.error "[SupportAgentChatsController] #{e.message}\n#{Array(e.backtrace).first(5).join("\n")}"
      render_failed_answer("Chat error: #{e.message}", message, status: :internal_server_error)
    end
  end

  # The agent (authorized), the record the window is about (authorized), and the user's sessions on it.
  def load_window
    @support_agent = SupportAgent.find(params[:support_agent_id])
    authorize @support_agent, :show?
    chattable = find_chattable
    # H3-3 - no (or no usable) record named: the window is about the agent, as before
    @target = chattable || @support_agent
    # H3-1, H3-2 - a named record must be one the user may see
    authorize_target if chattable
  end

  # H3-1, H3-2, H3-X - each record's own policy decides (show?). A class with no policy counts as
  # refused, not as a server error. Raises Pundit::NotAuthorizedError, handled by deny_access.
  def authorize_target
    authorize @target, :show?
  rescue Pundit::NotDefinedError
    # No policy for this record type: refuse it like any other unauthorized record
    raise Pundit::NotAuthorizedError, "not allowed to chat about #{@target.class.name}"
  end

  # The conversation the window opens on: the latest, unless it has been idle past GenericChatAgent's
  # limit — then a new one, as asking would start one anyway (E18). Reopening it from the list continues it.
  def current_window_session
    latest = window_sessions.order(updated_at: :desc).first
    latest unless latest.nil? || GenericChatAgent.session_expired?(latest)
  end

  # X7, E13 — only the current user's conversations with this agent about this record.
  def window_sessions
    AgentChatSession.where(chattable: @target, support_agent: @support_agent, analyst_id: current_user.id)
  end

  def window_locals
    { support_agent: @support_agent, chattable: @target, session: @session, sessions: window_sessions }
  end

  # Replaces the whole window frame: the thread now holds the answer, and the list the conversation.
  def render_window_stream
    render turbo_stream: turbo_stream.replace(helpers.agent_chat_frame_id(@support_agent),
                                              partial: "support_agents/chat_window", locals: window_locals)
  end

  # The pending question and answer become this attempt's question and failed answer, under ids of
  # their own — so a retry's pending pair (the composer's fixed ids) is found again, however many times
  # it fails (X1) — and the question goes back in the box.
  def render_failed_answer(reason, message, status:)
    frame_id = helpers.agent_chat_frame_id(@support_agent)
    @session = window_sessions.find_by(id: params[:session_id]) if params[:session_id].present?
    attempt = SecureRandom.hex(6)
    question = AiChatItem.transient(dom_id: "#{frame_id}-question-#{attempt}", role: "user", content: message)
    item = AiChatItem.transient(dom_id: "#{frame_id}-answer-#{attempt}", role: "assistant", content: reason, status: :failed)
    render status: status, turbo_stream: [
      turbo_stream.replace("#{frame_id}-pending-question", partial: "ai_chat/question", locals: { item: question }),
      turbo_stream.replace("#{frame_id}-pending-answer", partial: "ai_chat/answer", locals: { item: item, mode: :rich }),
      turbo_stream.replace("#{frame_id}-composer", partial: "support_agents/chat_composer",
                                                   locals: window_locals.merge(value: message,
                                                                               new_session: params[:new_session].present?))
    ]
  end

  # The record named by chattable_type / chattable_id, or nil (the window is then about the agent).
  #
  # @return [ApplicationRecord, nil]
  def find_chattable
    return nil unless params[:chattable_type].present? && params[:chattable_id].present?

    # H3-3 - resolve the name without constantize: an unknown name is nil, never an arbitrary constant
    klass = params[:chattable_type].to_s.safe_constantize
    # H3-3 - only concrete models (Kernel, ActiveRecord::Base, ApplicationRecord are not)
    return nil unless klass.is_a?(Class) && klass < ApplicationRecord && !klass.abstract_class?

    # An unknown id is nil too: the window falls back to the agent, as before
    klass.find_by(id: params[:chattable_id])
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
