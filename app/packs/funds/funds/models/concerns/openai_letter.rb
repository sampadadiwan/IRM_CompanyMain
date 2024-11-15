class OpenaiLetter
  OPENAI_API_KEY = Rails.application.credentials[:OPENAI_API_KEY]
  attr_accessor :openai_client

  def initialize
    Rails.logger.debug { "initialize using #{OPENAI_API_KEY}" }
    OpenAI.configure do |config|
      config.access_token = OPENAI_API_KEY # Required.
      config.organization_id = "org-Ewg4M3psKcHc5qo9hFeXyUk7"
    end
    @openai_client = OpenAI::Client.new
  end

  def test
    response = @openai_client.chat(
      parameters: {
        model: "gpt-3.5-turbo", # Required.
        messages: [{ role: "user", content: "Hello!" }], # Required.
        temperature: 0.7
      }
    )
    Rails.logger.debug response.dig("choices", 0, "message", "content")
  end
end
