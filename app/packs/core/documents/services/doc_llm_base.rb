# This class uses an llm to validate the data in the document and in the model (ex kyc)
# Example: Is the name in the pan card same as that in the kyc
# Example: Is the pan card number in the kyc same as that in the document
# Example: Is the date of birth in the kyc same as that in the document
# Is the address in the kyc same as that in the document
# Is the document valid or expired

# THis action will have access to the kyc, the document, and the checks to do for this document
class DocLlmBase < Trailblazer::Operation
  # Initialize the OpenAI client
  # model: The model whose data needs to be validated against the document (ex InvestorKyc, Offer etc)
  def init(ctx, model:, **)
    ctx[:llm_model] || "gpt-4o"
    temperature = ctx[:temperature] || 0.1
    access_token = Rails.application.credentials["OPENAI_API_KEY"]
    open_ai_client = OpenAI::Client.new(access_token:, llm_options: { model:, temperature: })

    ctx[:open_ai_client] = open_ai_client
    ctx[:open_ai_client].present?
  end

  # Since we deal with vision models, who can read images much better than PDFs, we convert the pdf or doc into image before sending to llm
  def convert_file_to_image(ctx, model:, document:, **)
    folder_path = "tmp/#{model.class.name}/#{model.id}"
    # make the directory if it does not exist
    FileUtils.mkdir_p(folder_path) unless File.directory?(folder_path)
    # setup the image path
    image_path = "#{folder_path}/#{document.id}.png"
    ctx[:image_path] = image_path
    ctx[:folder_path] = folder_path

    if document.mime_type_includes?('pdf')
      # convert pdf to image
      document.file.download do |file|
        ImageService.pdf_to_image(document, file, folder_path, image_path)
      end
      true
    elsif document.mime_type_includes?('doc')
      # convert doc to image
    elsif document.mime_type_includes?('image')
      # Copy the file to the image_path
      document.file.download do |file|
        FileUtils.cp(file.path, image_path)
      end
      Rails.logger.debug "File is already an image"
      true
    else
      # raise error
      raise "Cannot conver to image"
    end
  end

  # Ensure assistant is deleted
  def cleanup(ctx, **)
    Rails.logger.debug "Cleaning up"
    ctx[:image_path]
    # assistant.delete

    # Delete the folder_path
    FileUtils.rm_rf(ctx[:folder_path]) if !Rails.env.development? && ctx[:folder_path] && File.directory?(ctx[:folder_path])
    true
  end

  def handle_errors(_ctx, **)
    Rails.logger.error "Error in #{self.class.name}"
    true
  end
end
