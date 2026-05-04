# frozen_string_literal: true

# Orchestrates a multi-turn chat conversation for a SupportAgent using RubyLLM.
# Resolves the appropriate chat provider, builds context, and persists messages.
#
# @see BaseChatProvider
# @see AgentChatSession

class GenericChatAgent < SupportAgentService
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

    ctx[:chat_session] = AgentChatSession.find_or_create_by!(
      chattable: ctx[:target],
      support_agent: @support_agent,
      analyst_id: analyst&.id
    )
  end

  def resolve_provider(ctx, **)
    ctx[:provider] = BaseChatProvider.resolve(
      support_agent: @support_agent,
      target: ctx[:chattable],
      analyst: ctx[:analyst]
    )
    ctx[:context] = ctx[:provider].build_context
  end

  def setup_ruby_llm_chat(ctx, **)
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
    chat = ctx[:chat]

    # Context is already embedded in the system instructions via setup_ruby_llm_chat.
    # Do NOT duplicate it in the user message — Gemini interprets "use this data to answer"
    # as a signal to compute from context, which prevents it from calling tools like
    # the stress scenario tool for "what if" questions.
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = chat.ask(ctx[:user_message])
    Rails.logger.info("[Generic chat agent] execute_chat took #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round}ms ")
    ctx[:ai_response] = response.content.to_s.presence || "(no response)"
  rescue StandardError => e
    Rails.logger.error "[GenericChatAgent] chat.ask failed: #{e.class} — #{e.message}"
    ctx[:ai_response] = "I'm sorry, I encountered an error processing your request. Please try again."
  end

  def persist_conversation(ctx, **)
    session = ctx[:chat_session]

    # Save user message
    session.agent_chat_messages.create!(role: "user", content: ctx[:user_message])

    # Save assistant response
    session.agent_chat_messages.create!(role: "assistant", content: ctx[:ai_response])
  end

  def load_conversation_history(chat_session, chat)
    chat_session.agent_chat_messages.order(:created_at).each do |msg|
      chat.add_message(role: msg.role, content: msg.content)
    end
  end
end
