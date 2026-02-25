# frozen_string_literal: true

# Orchestrates a multi-turn chat conversation for a SupportAgent using LangChain.
# Resolves the appropriate chat provider, builds context, and persists messages.
#
# @see BaseChatProvider
# @see AgentChatSession

class GenericChatAgent < SupportAgentService
  STEP_LABELS = {
    initialize_chat: "Initialize",
    resolve_provider: "Load Provider",
    setup_langchain_assistant: "Setup LLM",
    execute_chat: "Execute Chat",
    persist_conversation: "Save Messages"
  }.freeze

  step :initialize_chat
  step :resolve_provider
  step :setup_langchain_assistant
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

  def setup_langchain_assistant(ctx, **)
    llm = LlmService.langchain_llm(
      entity: @support_agent.entity,
      model: @support_agent.chat_model
    )
    provider = ctx[:provider]

    instructions = provider.system_prompt
    instructions += "\n\nCONTEXT:\n#{ctx[:context]}" if ctx[:context].present?

    assistant = Langchain::Assistant.new(
      llm: llm,
      instructions: instructions,
      tools: provider.tools
    )

    load_conversation_history(ctx[:chat_session], assistant)
    ctx[:assistant] = assistant
  end

  def execute_chat(ctx, **)
    assistant = ctx[:assistant]

    # Prepend context to user message if this is a fresh conversation (no history)
    user_msg = if ctx[:context].present? && ctx[:chat_session].agent_chat_messages.empty?
                 "Here is the data you should use to answer my questions:\n\n#{ctx[:context]}\n\nMy question: #{ctx[:user_message]}"
               else
                 ctx[:user_message]
               end

    assistant.add_message(content: user_msg)
    assistant.run(auto_tool_execution: true)
    ctx[:ai_response] = assistant.messages.last.content
  end

  def persist_conversation(ctx, **)
    session = ctx[:chat_session]

    # Save user message
    session.agent_chat_messages.create!(role: "user", content: ctx[:user_message])

    # Save assistant response
    session.agent_chat_messages.create!(role: "assistant", content: ctx[:ai_response])
  end

  def load_conversation_history(chat_session, assistant)
    chat_session.agent_chat_messages.order(:created_at).each do |msg|
      role = if msg.role == "assistant"
               assistant.llm.is_a?(Langchain::LLM::GoogleGemini) ? "model" : "assistant"
             else
               msg.role
             end
      assistant.add_message(role: role, content: msg.content)
    end
  end
end
