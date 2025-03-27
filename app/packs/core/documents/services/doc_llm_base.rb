# This class uses an llm to validate the data in the document and in the model (ex kyc)
# Example: Is the name in the pan card same as that in the kyc
# Example: Is the pan card number in the kyc same as that in the document
# Example: Is the date of birth in the kyc same as that in the document
# Is the address in the kyc same as that in the document
# Is the document valid or expired

# THis action will have access to the kyc, the document, and the checks to do for this document
class DocLlmBase < Trailblazer::Operation
  # Initialize the LLM client
  def init(ctx, provider: :openai, llm_model: "gpt-4o", temperature: 0.1, **)
    Rails.logger.debug { "Initializing LLM client with provider: #{provider}, model: #{llm_model}, temperature: #{temperature}" }
    ctx[:provider] = provider
    ctx[:llm_model] = llm_model
    ctx[:llm_client] = initialize_llm(provider, llm_model, temperature)
    ctx[:llm_client].present?
  end

  # Convert the document to images for better LLM vision processing
  def convert_file_to_image(ctx, document:, **)
    DocUtils.convert_file_to_image(ctx, document:)
  end

  # Cleanup (remove temp images, etc.)
  def cleanup(ctx, **)
    Rails.logger.debug "Cleaning up"
    FileUtils.rm_rf(ctx[:folder_path]) if ctx[:folder_path] && File.directory?(ctx[:folder_path])
    true
  end

  def handle_errors(_ctx, **)
    Rails.logger.error "Error in #{self.class.name}"
    true
  end

  private

  def initialize_llm(provider, llm_model, temperature)
    case provider.to_sym
    when :openai
      Langchain::LLM::OpenAI.new(
        api_key: Rails.application.credentials["OPENAI_API_KEY"],
        default_options: { model: llm_model, temperature: temperature }
      )
    when :anthropic
      Langchain::LLM::Anthropic.new(
        api_key: Rails.application.credentials["ANTHROPIC_API_KEY"],
        default_options: { model: llm_model, temperature: temperature }
      )
    when :gemini
      Langchain::LLM::GoogleGemini.new(
        api_key: Rails.application.credentials["GOOGLE_GEMINI_API_KEY"],
        default_options: { model: llm_model, temperature: temperature }
      )
    # Add other providers as needed
    else
      raise ArgumentError, "Unsupported provider: #{provider}"
    end
  end
end
