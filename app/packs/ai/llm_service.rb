# The LlmService class serves as a high-level interface for interacting with
# various Large Language Models (LLMs) through the `langchain` gem. It abstracts
# the details of provider-specific initialization and request formatting.
class LlmService
  # The LlmInitializer module is included as a class-level extension,
  # making its `initialize_llm` factory method available directly on the LlmService class.
  extend LlmInitializer

  # The primary method for sending a prompt to an LLM and receiving a response.
  # It handles default provider/model selection and constructs the API request.
  #
  # @param prompt [String] The text prompt to send to the LLM.
  # @param provider [String, nil] The desired LLM provider (e.g., 'gemini', 'openai').
  #   Defaults to the `AI_CHECKS_PROVIDER` environment variable or 'gemini'.
  # @param llm_model [String, nil] The specific model to use.
  #   Defaults to the `AI_CHECKS_MODEL` environment variable or a specific Gemini model.
  # @return [String] The text content of the LLM's response.
  def self.chat(prompt:, provider: nil, llm_model: nil, format: :text)
    # Set default provider and model from environment variables if not explicitly provided.
    # This allows for easy configuration in different environments (development, production).
    provider ||= ENV.fetch('AI_CHECKS_PROVIDER', 'gemini')
    llm_model ||= ENV.fetch('AI_CHECKS_MODEL', 'gemini-2.5-flash-preview-05-20')

    Rails.logger.debug { "LlmService: Using provider: #{provider}, model: #{llm_model}" }

    # Use the factory method from LlmInitializer to get a pre-configured client instance.
    # A low temperature (0.1) is set to encourage deterministic and factual responses.
    llm = initialize_llm(provider, llm_model, 0.1, format)

    # Call the #chat method on the Langchain LLM client.
    # The payload is structured according to the `langchain` gem's requirements for Gemini,
    # with the prompt wrapped in a message hash.
    response = llm.chat(
      messages: [
        { role: "user", parts: [{ text: prompt }] }
      ],
      model: llm_model # Explicitly pass the model to the chat call
    )
    # Extract the main text content from the provider's response object.
    response.chat_completion
  end
end
