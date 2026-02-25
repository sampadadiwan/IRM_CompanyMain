# frozen_string_literal: true

# DefaultChatProvider is a basic fallback chat provider for any SupportAgent.
# It provides a generic system prompt with no domain-specific context or tools.
class DefaultChatProvider < BaseChatProvider
  def system_prompt
    custom_prompt = support_agent.chat_config["system_prompt"]
    return custom_prompt if custom_prompt.present?

    <<~PROMPT
      You are a helpful AI assistant for #{support_agent.entity&.name || 'the organization'}.
      Agent: #{support_agent.name}
      User: #{analyst&.name || 'Unknown'}

      Guidelines:
      - Be professional and concise
      - Base responses on facts
      - If you don't know something, say so honestly
    PROMPT
  end

  def build_context
    ""
  end

  def tools
    []
  end
end
