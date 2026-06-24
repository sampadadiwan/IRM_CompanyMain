# frozen_string_literal: true

# Orchestrates a multi-turn chat conversation for a SupportAgent using RubyLLM.
# Resolves the appropriate chat provider, builds context, and persists messages.
#
# @see BaseChatProvider
# @see AgentChatSession
#
class GenericChatAgent < SupportAgentService
  class MaxToolIterationsExceeded < StandardError; end

  DESCRIPTION = "Provides multi-turn AI chat for any configured support agent using context-aware chat providers."

  LONG_DESCRIPTION = <<~DESC
    Orchestrates multi-turn AI chat conversations for any configured support agent.
    Resolves the appropriate chat provider based on the agent type, builds context from the
    target record, and persists all messages to an AgentChatSession for resumable conversations.

    Chat providers:
    • DefaultChatProvider — general-purpose chat with system context from the agent's configuration.
    • PortfolioCompanyChatProvider — enriches context with portfolio company data and KPI history.
    • PortfolioAssistantChatProvider — provides portfolio-level analysis and cross-company context.
    • CashFlowChatProvider — loads cash flow data and fund positions for financial Q&A.

    Steps: Initialize → Resolve Provider → Setup LLM → Execute Chat → Save Messages.
    Messages are persisted so conversations are resumable across sessions. Used as the backend
    for the chat panel on the Support Agent show page.
  DESC

  STEP_LABELS = {
    initialize_chat: "Initialize",
    resolve_provider: "Load Provider",
    setup_ruby_llm_chat: "Setup LLM",
    execute_chat: "Execute Chat",
    persist_conversation: "Save Messages"
  }.freeze

  step :initialize_chat
  step :resolve_provider
  step :setup_ruby_llm_chat
  step :execute_chat
  step :persist_conversation

  private

  def initialize_chat(ctx, **)
    @support_agent = SupportAgent.find(ctx[:support_agent_id])
    ctx[:support_agent] = @support_agent

    analyst = ctx[:analyst_id].present? ? User.find(ctx[:analyst_id]) : nil
    ctx[:analyst] = analyst
    ctx[:chattable] = ctx[:target]

    # @return [AgentChatSession] active session, or a new one if the last session is idle
    # Starts a new session if the previous one has been idle for more than 30 minutes,
    # preventing unbounded context growth across unrelated support queries.
    existing_session = AgentChatSession.where(
      chattable: ctx[:target],
      support_agent: @support_agent,
      analyst_id: analyst&.id
    ).order(updated_at: :desc).first

    ctx[:chat_session] = if existing_session.nil? || session_expired?(existing_session)
                           AgentChatSession.create!(
                             chattable: ctx[:target],
                             support_agent: @support_agent,
                             analyst_id: analyst&.id
                           )
                         else
                           existing_session
                         end
    ctx[:escalation_notice] = "Note: Your earlier query has been escalated to our support team and is being reviewed." if ctx[:chat_session].escalated?

    true
  end

  def resolve_provider(ctx, **)
    return true if ctx[:skip_to_persist]

    ctx[:provider] = BaseChatProvider.resolve(
      support_agent: @support_agent,
      target: ctx[:chattable],
      analyst: ctx[:analyst]
    )
    ctx[:context] = ctx[:provider].build_context
    ctx[:provider].chat_session = ctx[:chat_session] if ctx[:provider].respond_to?(:chat_session=)
    true
  end

  def setup_ruby_llm_chat(ctx, **)
    return true if ctx[:skip_to_persist]

    provider = ctx[:provider]

    instructions = provider.system_prompt
    instructions += "\n\nCONTEXT:\n#{ctx[:context]}" if ctx[:context].present?

    chat = LlmService.ruby_llm_chat(
      entity: @support_agent.entity,
      model: @support_agent.chat_model
    )
    chat.with_instructions(instructions)
    chat.with_tools(*provider.tools) if provider.tools.any?

    load_conversation_history(ctx[:chat_session], chat)
    ctx[:chat] = chat
  end

  def execute_chat(ctx, **)
    return true if ctx[:skip_to_persist]

    chat = ctx[:chat]
    provider = ctx[:provider]

    register_tool_call_cap(chat, provider)

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = chat.ask(ctx[:user_message])
    Rails.logger.info("[Generic chat agent] execute_chat took #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round}ms ")
    ctx[:ai_response] = response.content.to_s.presence || "(no response)"
    true
  rescue MaxToolIterationsExceeded => e
    Rails.logger.warn "[GenericChatAgent] #{e.message} — auto-escalating session #{ctx[:chat_session]&.id}"
    auto_escalate(ctx)
    true
  rescue StandardError => e
    Rails.logger.error "[GenericChatAgent] chat.ask failed: #{e.class} — #{e.message}"
    ctx[:ai_response] = "I'm sorry, I encountered an error processing your request. Please try again."
    true
  end

  def persist_conversation(ctx, **)
    session = ctx[:chat_session]

    # Save user message
    session.agent_chat_messages.create!(role: "user", content: ctx[:user_message])

    # Prepend escalation notice if session was previously escalated
    ai_response = ctx[:ai_response]
    ai_response = "#{ctx[:escalation_notice]}\n\n#{ai_response}" if ctx[:escalation_notice].present?

    # Save assistant response
    assistant_message = session.agent_chat_messages.create!(role: "assistant", content: ai_response)

    # Enqueue LLM-as-judge for CS agent responses (only if judge is enabled)
    ResponseJudgeJob.perform_later(assistant_message.id) if @support_agent.agent_type == "CustomerSupportAgent" && @support_agent.entity&.entity_setting&.cs_judge_enabled?
    true
  end

  def load_conversation_history(chat_session, chat)
    chat_session.agent_chat_messages.order(:created_at).each do |msg|
      chat.add_message(role: msg.role, content: msg.content)
    end
  end

  # Registers a before_tool_call hook that raises after max_tool_iterations calls.
  # @param chat [RubyLLM::Chat] the chat instance
  # @param provider [BaseChatProvider] the current provider
  # @return [void]
  def register_tool_call_cap(chat, provider)
    max_iterations = provider.max_tool_iterations
    return unless max_iterations

    tool_call_count = 0
    chat.before_tool_call do |_tool_call|
      tool_call_count += 1
      raise MaxToolIterationsExceeded, "Tool call limit (#{max_iterations}) exceeded" if tool_call_count > max_iterations
    end
  end

  # Auto-escalates the session to the CS team when the tool cap is exceeded.
  # Only fires for CustomerSupportAgent; other agent types get a generic error.
  # @param ctx [Hash] the Trailblazer context
  # @return [void]
  def auto_escalate(ctx)
    unless ctx[:support_agent]&.agent_type == "CustomerSupportAgent"
      ctx[:ai_response] = "I'm sorry, I encountered an issue processing your request. Please try again."
      return
    end

    session = ctx[:chat_session]
    analyst = ctx[:analyst]
    entity = ctx[:provider]&.support_agent&.entity

    if session && analyst && entity
      CustomerSupportEscalationService.escalate!(
        session: session,
        user: analyst,
        entity: entity,
        reason: "max_iterations",
        summary: "Auto-escalated: agent exceeded #{ctx[:provider].max_tool_iterations} tool call iterations without producing a final answer."
      )
      ctx[:ai_response] = "I wasn't able to find a complete answer after several attempts. " \
                          "I've connected you with the Caphive support team — they'll review your conversation and get back to you shortly."
    else
      ctx[:ai_response] = "I'm sorry, I encountered an issue processing your request. Please try again or contact support."
    end
  end

  # @param session [AgentChatSession] the session to check
  # @return [Boolean] true if the session's last message is older than 30 minutes
  SESSION_IDLE_TIMEOUT = 30.minutes # rubocop:disable Lint/UselessConstantScoping

  def session_expired?(session)
    last_message = session.agent_chat_messages.order(created_at: :desc).first
    return true if last_message.nil?

    last_message.created_at < SESSION_IDLE_TIMEOUT.ago
  end
end
