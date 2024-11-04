class AiAssistant
  include Langchain::DependencyHelper
  include Rails.application.routes.url_helpers

  def initialize(data_manager, instructions)
    @data_manager = data_manager
    @instructions = instructions
  end

  def assistant
    @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "gpt-4o" })

    @assistant ||= Langchain::Assistant.new(
      llm: @llm,
      tools: [@data_manager, Langchain::Tool::Calculator.new],
      instructions: @instructions
    )

    @assistant
  end

  def query(query_string)
    assistant.add_message(content: query_string)
    assistant.run(auto_tool_execution: true)
    assistant.messages[-1].content
  end

  def self.send_notification(message, user_id, level = "success")
    Rails.logger.debug message
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present? && message.present?
  end
end
