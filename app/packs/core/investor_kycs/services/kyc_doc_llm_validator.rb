# This class uses an llm to validate the data in the document and in the kyc
# Example: Is the name in the pan card same as that in the kyc
# Example: Is the pan card number in the kyc same as that in the document
# Example: Is the date of birth in the kyc same as that in the document
# Is the address in the kyc same as that in the document
# Is the document valid or expired

# THis action will have access to the kyc, the document, and the checks to do for this document
class KycDocLlmValidator < Trailblazer::Operation
  step :convert_file_to_image
  step :send_file_to_llm
  step :run_checks_with_llm
  step :save_check_results
  step :cleanup_assistant
  left :handle_errors

  # Initialize the OpenAI client
  def initialize
    # @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "o1-mini" })
    @client = OpenAI::Client.new(access_token: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "o1-mini" })
  end

  # Since we deal with vision models, who can read images much better than PDFs, we convert the pdf or doc into image before sending to llm
  def convert_file_to_image(_ctx, document:, **)
    if document.mime_type_includes?('pdf')
    # convert pdf to image
    elsif document.mime_type_includes?('doc')
    # convert doc to image
    elsif document.mime_type_includes?('image')
      # do nothing
      logger.debug { "File is already an image" }
    else
      # raise error
      raise "Cannot conver to image"
    end
  end

  # Here we are specifically coding for OpenAI models which are multivision, we DO NOT use langchain.rb gem
  def send_file_to_llm(ctx, investor_kyc:, document:); end

  def run_checks_with_llm(ctx, investor_kyc:, assistant:, checks_to_perform:, **)
    # At this point we should have the assistant to which the file is sent
  end

  def save_check_results(_ctx, investor_kyc:, checks_results:, **)
    investor_kyc.automatic_validations = checks_results
    investor_kyc.save
  end

  # Ensure assistant is deleted
  def cleanup_assistant(ctx, assistant:, **); end

  def handle_errors(ctx, **); end
end
