# This class uses an llm to validate the data in the document and in the model (ex kyc)
# Example: Is the name in the pan card same as that in the kyc
# Example: Is the pan card number in the kyc same as that in the document
# Example: Is the date of birth in the kyc same as that in the document
# Is the address in the kyc same as that in the document
# Is the document valid or expired

# THis action will have access to the kyc, the document, and the checks to do for this document
class DocLlmValidator < Trailblazer::Operation
  step :init
  step :convert_file_to_image
  step :run_checks_with_llm
  step :save_check_results
  step :cleanup
  left :handle_errors

  # Initialize the OpenAI client
  # model: The model whose data needs to be validated against the document (ex InvestorKyc, Offer etc)
  # document: The document to be used in validation (ex PAN, Tax document, Passport etc)
  def init(ctx, model:, document:, **)
    # @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "o1-mini" })
    open_ai_client = OpenAI::Client.new(access_token: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "o1-mini" })
    ctx[:open_ai_client] = open_ai_client
    ctx[:doc_questions] = model.doc_questions.where(document_name: document.name)
    Rails.logger.debug { "Initialized Doc LLM Validator for #{model} with #{document.name}" }
    true
  end

  # Since we deal with vision models, who can read images much better than PDFs, we convert the pdf or doc into image before sending to llm
  def convert_file_to_image(ctx, document:, **)
    # make the directory if it does not exist
    FileUtils.mkdir_p("tmp/KycDocLlmValidator") unless File.directory?("tmp/KycDocLlmValidator")
    # setup the image path
    image_path = "tmp/KycDocLlmValidator/#{document.id}.png"
    ctx[:image_path] = image_path

    if document.mime_type_includes?('pdf')
      # convert pdf to image
      document.file.download do |file|
        image = MiniMagick::Image.open(file.path)
        image.format "png"
        image.write(image_path)
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

  def encode_image(image_path:, **)
    Rails.logger.debug { "Encoding image #{image_path}" }
    file_extension = File.extname(image_path).delete(".")
    image = Base64.encode64(File.read(image_path))
    "data:image/#{file_extension};base64,#{image}"
  end

  # # Usage
  # input_string = "Is the name in the document $full_name and the PAN number $pan_number?"
  # variables = extract_variables(input_string)
  # puts variables
  # Output:
  # ["full_name", "pan_number"]
  def extract_variables(text)
    # This will return an array of variable names without the '$'
    text.scan(/\$(\w+)/).flatten
  end

  # Replace the variables in the checks with the actual values from the kyc
  def replace_variables(doc_questions, model)
    new_checks = []

    doc_questions.each do |doc_question|
      check = doc_question.question

      # Extract the variables from the check
      evs = extract_variables(check)
      if evs.empty?
        # If there are no variables in the check, just add the check to the new_checks
        interpolated_question = "Question: #{check}. Response Format Hint: #{doc_question.response_hint_text}"
        new_checks << interpolated_question
      else
        # Replace the variables in the check with the actual values from the kyc
        evs.each do |var|
          interpolated_question = check.gsub!("$#{var}", model.send(var.to_sym))
          new_checks << "Question: #{interpolated_question}. Response Format Hint: #{doc_question.response_hint_text}"
        end
      end
      # Set the interpolated question in the doc_question
      doc_question.interpolated_question = interpolated_question
    end

    new_checks
  end

  # Run the checks with the llm
  # checks is a list of questions to ask the llm about the document
  # Example: checks = ["Is the name $full_name ?", "Is there a date of birth", "What is the PAN number?", "Is the pan number $PAN ?"]
  def run_checks_with_llm(ctx, model:, doc_questions:, open_ai_client:, **)
    # Replace the variables in the checks with the actual values from the kyc
    new_checks = replace_variables(doc_questions, model)
    Rails.logger.debug { "Running checks with LLM: #{new_checks}" }

    messages = new_checks.map { |check| { type: "text", text: check } } + [
      { type: "text", text: "Return the answers to all the questions as a json document without any formatting or enclosing tags. In the json document returned, create the key as specified by the Response Format Hint and the value is a json with answer to the specific Question and explanation for the answer. Example {'The question that was input': {answer: 'Your answer', explanation: 'Your explanation for the answer given'}} " },
      { type: "image_url",
        image_url: {
          url: encode_image(image_path: ctx[:image_path])
        } }
    ]

    # Run the checks with the llm
    response = open_ai_client.chat(
      parameters: {
        model: "gpt-4o", # Required.
        response_format: { type: "json_object" },
        messages: [{ role: "user", content: messages }] # Required.
      }
    )

    # Get the results from the response
    ctx[:doc_question_answers] = response.dig("choices", 0, "message", "content")
    Rails.logger.debug ctx[:doc_question_answers]
    true
  end

  VALIDATION_RESPONSES = %w[yes no true false].freeze
  def save_check_results(_ctx, model:, document:, doc_question_answers:, **)
    model.doc_question_answers ||= {}
    model.doc_question_answers[document.name] = JSON.parse(doc_question_answers)
    model.doc_question_answers[document.name].each do |question, answer|
      # Need better check for extraction
      unless VALIDATION_RESPONSES.include?(answer.to_s.downcase)
        # Save any extracted data from the document to the model custom fields
        if model.respond_to?(question.to_sym)
          model.send(:"#{question}=", answer)
        else
          model.properties[question] = answer
        end
      end
    end

    all_docs_valid = true
    # Scan the answers across all documents which have been examined by the llm to see if any of them are false
    model.doc_question_answers.each do |doc_name, qna|
      Rails.logger.debug { "Validating #{doc_name}" }
      qna.each do |question, response|
        answer = response["answer"]
        Rails.logger.debug { "Checking #{doc_name}, Question: #{question} Answer: #{answer}" }
        # Need to make this more deterministic in the future
        next unless answer.to_s.downcase == "no" || answer.to_s.downcase == "false"

        # Validation has failed. Something is mismatched between the document and the model
        Rails.logger.debug { "Validation failed for #{model}, #{doc_name}, #{question}" }
        all_docs_valid &&= false
      end
    end

    # Tell the model that the documents have been validated
    model.mark_as_validated(all_docs_valid)
  end

  # Ensure assistant is deleted
  def cleanup(ctx, **)
    Rails.logger.debug "Cleaning up"
    image_path = ctx[:image_path]
    # Check if tmp image_path is present and delete
    File.delete(image_path) if image_path && File.exist?(image_path)
    # assistant.delete
    true
  end

  def handle_errors(ctx, **); end
end
