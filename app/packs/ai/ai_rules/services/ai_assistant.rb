class AiAssistant
  include Langchain::DependencyHelper
  include Rails.application.routes.url_helpers

  def initialize(data_manager, instructions)
    @data_manager = data_manager
    @instructions = instructions
    @tools = [Langchain::Tool::Calculator.new]
    @tools << @data_manager if @data_manager.present?
  end

  def assistant
    @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "gpt-4o" })

    @assistant ||= Langchain::Assistant.new(
      llm: @llm,
      tools: @tools,
      instructions: @instructions
    )

    @assistant
  end

  def addDocAsImage(document)
    ctx = {}
    DocUtils.convert_file_to_image(ctx, document:)
    assistant.add_message(
      content: "This is the contents of the document #{document.name}",
      image_url: ImageService.encode_image(ctx[:image_path])
    )
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

  QNA_INSTRUCTIONS = "You are a research assistant who will be asked questions. You only looks at the data provided and produces detailed answers (min 5 lines of text) based on that data. You are not allowed to look at any external sources. The output should be in the form of a json object with the question as the key and the answer as the value. The answer should be a string and the explanation should be a string. For example {question: 'The question that was input', answer: 'Your answer', key_facts: 'Extract all numbers and data supporting the answer'. do not add ```json to the output.".freeze

  def self.test
    assistant = AiAssistant.new(nil, QNA_INSTRUCTIONS)
    assistant.addDocAsImage(Document.find(4892))
    assistant.query("What are the key points in this document?")
  end
end
