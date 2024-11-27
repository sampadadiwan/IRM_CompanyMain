class AiAssistant
  include Langchain::DependencyHelper
  include Rails.application.routes.url_helpers

  def initialize(data_manager, instructions, tools: [Langchain::Tool::Calculator.new])
    @data_manager = data_manager
    @instructions = instructions
    @tools = tools
    @tools << @data_manager if @data_manager.present?
  end

  def assistant
    @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { request_timeout: 600 }, default_options: {request_timeout: 600, chat_model: "gpt-4o-mini" })

    @assistant ||= Langchain::Assistant.new(
      llm: @llm,
      tools: @tools,
      instructions: @instructions
    )

    @assistant
  end

  def add_doc_as_image(document)
    ctx = {}
    DocUtils.convert_file_to_image(ctx, document:)
    assistant.add_message(
      content: "This is the contents of the document #{document.name}",
      image_url: ImageService.encode_image(ctx[:image_path])
    )
  end

  def add_doc_as_text(document)
    document.file.download do |file|
      assistant.add_message(content: "This is the contents of the document #{document.name}")
      assistant.add_message(content: File.read(file.path))
    end
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

  QNA_INSTRUCTIONS = "You are a financial analyst providing a detailed summary of a pitch deck.".freeze

  def self.test
    assistant = AiAssistant.new(nil, QNA_INSTRUCTIONS)
    assistant.add_doc_as_image(Document.find(4892))
    assistant.query("What are the key points in this document? provide a comprehensive analysis rather than a terse summary, please.")
  end
end
