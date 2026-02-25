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
    llm_model ||= ENV.fetch('AI_CHECKS_MODEL', ENV.fetch('DEFAULT_MODEL'))

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

  def self.ruby_llm_chat(entity: nil)
    if entity
      custom_context = RubyLLM.context do |config|
        config.openai_api_key = entity.entity_setting.openai_api_key || Rails.application.credentials["OPENAI_API_KEY"]
        config.gemini_api_key = entity.entity_setting.gemini_api_key || Rails.application.credentials["GOOGLE_GEMINI_API_KEY"]
        config.anthropic_api_key = entity.entity_setting.anthropic_api_key || Rails.application.credentials["ANTHROPIC_API_KEY"]
        config.openrouter_api_key = entity.entity_setting.openrouter_api_key || Rails.application.credentials["OPENROUTER_API_KEY"]
        config.use_new_acts_as = true
      end

      RubyLLM.chat(
        model: entity.entity_setting.default_llm_model || ENV.fetch("DEFAULT_MODEL", nil),
        context: custom_context
      )
    else
      # Default configuration without entity-specific API keys
      Rails.logger.debug "LlmService: Warning! Using default RubyLLM configuration"
      RubyLLM.chat(model: ENV.fetch("DEFAULT_MODEL", nil))
    end
  end

  # Returns a Langchain LLM instance with entity-specific API keys
  # Supports OpenAI, Anthropic, and Gemini — mirrors ruby_llm_chat's key resolution
  def self.langchain_llm(entity: nil, model: nil, temperature: 0.7, provider: nil)
    setting = entity&.entity_setting
    model ||= setting&.default_llm_model || ENV.fetch('DEFAULT_MODEL', 'gpt-4o-mini')
    provider ||= detect_provider(model)
    model = normalize_model(provider, model)

    case provider.to_sym
    when :openai
      api_key = setting&.openai_api_key.presence ||
                Rails.application.credentials["OPENAI_API_KEY"] ||
                ENV.fetch('OPENAI_API_KEY', nil)
      raise "OpenAI API key not configured" unless api_key

      Langchain::LLM::OpenAI.new(
        api_key: api_key,
        default_options: { model: model, temperature: temperature }
      )
    when :anthropic
      api_key = setting&.anthropic_api_key.presence ||
                Rails.application.credentials["ANTHROPIC_API_KEY"] ||
                ENV.fetch('ANTHROPIC_API_KEY', nil)
      raise "Anthropic API key not configured" unless api_key

      Langchain::LLM::Anthropic.new(
        api_key: api_key,
        default_options: { model: model, temperature: temperature }
      )
    when :gemini
      api_key = setting&.gemini_api_key.presence ||
                Rails.application.credentials["GOOGLE_GEMINI_API_KEY"] ||
                ENV.fetch('GOOGLE_GEMINI_API_KEY', nil)
      raise "Gemini API key not configured" unless api_key

      Langchain::LLM::GoogleGemini.new(
        api_key: api_key,
        default_options: { chat_model: model, temperature: temperature }
      )
    else
      raise ArgumentError, "Unsupported provider: #{provider}"
    end
  end

  # Detects provider from model name
  def self.detect_provider(model)
    case model.to_s
    when /^gpt|^o1|^o3/i then :openai
    when /^claude/i then :anthropic
    when /^gemini/i then :gemini
    else :openai
    end
  end

  # Some older Gemini aliases were sunset; map them to a supported fallback.
  def self.normalize_model(provider, model)
    return model if model.blank?
    return model unless provider.to_sym == :gemini

    fallback = ENV.fetch("GEMINI_FALLBACK_MODEL", "gemini-2.5-flash")

    case model
    when "gemini-1.5-pro-latest", "gemini-1.5-pro", "gemini-1.5-flash-latest", "gemini-1.5-flash"
      Rails.logger.warn("LlmService: '#{model}' is deprecated, falling back to '#{fallback}'")
      fallback
    else
      model
    end
  end
end
