# The LlmInitializer module provides a centralized factory method for creating
# instances of different Large Language Model (LLM) clients from the `langchain` gem.
# This approach encapsulates the specific initialization logic for each provider,
# making it easy to switch between or add new providers in the future.
module LlmInitializer
  # Initializes and returns an LLM client based on the specified provider.
  #
  # @param provider [Symbol, String] The LLM provider to use (e.g., :openai, :anthropic, :gemini).
  # @param llm_model [String] The specific model name to be used for the provider.
  # @param temperature [Float] The creativity/randomness of the model's output (0.0 - 1.0).
  # @return [Object] An instance of the corresponding Langchain LLM client.
  # @raise [ArgumentError] If the specified provider is not supported.
  def initialize_llm(provider, llm_model, temperature, format = :text)
    Rails.logger.debug { "Initializing LLM client with provider: #{provider}, model: #{llm_model}, temperature: #{temperature}" }
    case provider.to_sym
    when :openai
      # Initializes the OpenAI client
      Langchain::LLM::OpenAI.new(
        api_key: Rails.application.credentials[:OPENAI_API_KEY],
        default_options: { model: llm_model, temperature: temperature }
      )
    when :anthropic
      # Initializes the Anthropic client
      Langchain::LLM::Anthropic.new(
        api_key: Rails.application.credentials[:ANTHROPIC_API_KEY],
        default_options: { model: llm_model, temperature: temperature }
      )
    when :gemini
      # Initializes the Google Gemini client. Note the additional `generation_config`
      # for certain use cases the response should be in JSON format
      response_mime_type = format == :json ? 'application/json' : 'text/plain'
      Langchain::LLM::GoogleGemini.new(
        api_key: Rails.application.credentials[:GOOGLE_GEMINI_API_KEY],
        default_options: { model: llm_model, temperature: temperature, generation_config: {
          response_mime_type: response_mime_type
        } }
      )
    # Add other providers as needed
    else
      # Raises an error if the provider is not in the list of supported providers.
      raise ArgumentError, "Unsupported provider: #{provider}"
    end
  end
end
