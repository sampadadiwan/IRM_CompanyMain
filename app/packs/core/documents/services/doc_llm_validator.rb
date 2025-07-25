# This class uses an llm to validate the data in the document and in the model (ex kyc)
# Example: Is the name in the pan card same as that in the kyc
# Example: Is the pan card number in the kyc same as that in the document
# Example: Is the date of birth in the kyc same as that in the document
# Is the address in the kyc same as that in the document
# Is the document valid or expired

# THis action will have access to the kyc, the document, and the checks to do for this document
class DocLlmValidator < DocLlmBase
  NO_LIST = %w[no false].freeze

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
    super(ctx, provider: ENV.fetch('DOCUMENT_VALIDATION_PROVIDER', nil), llm_model: ENV.fetch('DOCUMENT_VALIDATION_MODEL', nil), temperature: 0.1, **)
    ctx[:doc_questions] ||= model.doc_questions.where(document_name: document.name)
    Rails.logger.debug { "Initialized Doc LLM Validator for #{model} with #{document.name}" }
    Rails.logger.debug "DocLlmValidator Error: No llm client" if ctx[:llm_client].blank?
    Rails.logger.debug "DocLlmValidator Error: No doc questions" if ctx[:doc_questions].blank?
    ctx[:llm_client].present? && ctx[:doc_questions].present?
  end

  # Run the checks with the llm
  # checks is a list of questions to ask the llm about the document
  # Example: checks = ["Is the name $full_name ?", "Is there a date of birth", "What is the PAN number?", "Is the pan number $PAN ?"]
  CHECK_INSTRUCTIONS = "Return the answers to all the questions as a JSON document without any formatting or ```json enclosing tags and only if it is present in the image presented to you. In the JSON document returned, use only the format below and not any other format. Be strict about the formatting

  Sample Response Format:
  {
    'key from response format hint' => { 'answer' => 'Your answer', 'explanation' => 'Your explanation for the answer given', question_type: 'Extraction, Validation or General question' },
    'key from response format hint' => { 'answer' => 'Your answer.', 'explanation' => 'Your explanation for the answer given', question_type: 'Extraction, Validation or General question' },
    ...
  }

  ".freeze

  def run_checks_with_llm(ctx, model:, doc_questions:, llm_client:, **) # rubocop:disable Metrics/MethodLength
    new_checks = VariableInterpolation.replace_variables(doc_questions, model)
    Rails.logger.debug { "Running checks with LLM: #{new_checks}" }

    model_name = ctx[:llm_model]
    image_data = Base64.strict_encode64(File.read(ctx[:image_path]))

    if llm_client.class.to_s.include?("Gemini") || ctx[:llm_provider] == :gemini
      # ✅ Gemini message format
      messages = new_checks.map { |check| { role: "user", parts: [{ text: check }] } }

      messages << {
        role: "user",
        parts: [{
          text: CHECK_INSTRUCTIONS
        }]
      }

      messages << {
        role: "user",
        parts: [{ inline_data: { mime_type: "image/png", data: image_data } }]
      }

      response = llm_client.chat(messages: messages, model: model_name, generation_config: { response_mime_type: 'application/json' })
      raw_response = response.raw_response

      if raw_response && raw_response["candidates"]&.first&.dig("content", "parts")
        ctx[:doc_question_answers] = raw_response["candidates"].first["content"]["parts"].pluck("text").join("\n")
      else
        Rails.logger.error { "Unexpected Gemini response structure: #{raw_response.inspect}" }
        return false
      end

    else
      # ✅ OpenAI message format
      messages = new_checks.map { |check| { role: "user", content: check } }

      messages << {
        role: "user",
        content: CHECK_INSTRUCTIONS
      }

      messages << {
        role: "user",
        content: [
          { type: "text", text: "Here's the image to extract data from:" },
          {
            type: "image_url",
            image_url: {
              url: "data:image/png;base64,#{image_data}"
            }
          }
        ]
      }

      response = llm_client.chat(model: model_name, messages: messages, generation_config: { response_mime_type: 'application/json' })
      ctx[:doc_question_answers] = response.completion
    end

    Rails.logger.debug ctx[:doc_question_answers]
    true
  rescue StandardError => e
    Rails.logger.error { "Error in running checks with LLM: #{e.message}" }
    raise e
  end

  VALIDATION_RESPONSES = %w[yes no true false].freeze
  # Save the results of the checks
  def save_check_results(ctx, model:, document:, doc_question_answers:, **)
    return true if ctx[:save_check_results] == false

    # Initialize the model's doc_question_answers if not already present
    model.doc_question_answers ||= {}
    # Parse and store the answers for the current document
    model.doc_question_answers[document.name] = JSON.parse(doc_question_answers)

    # Iterate through each question and its corresponding answer and explanation
    model.doc_question_answers[document.name].each do |question, answer_and_explanation|
      Rails.logger.debug { "Question: #{question}, Answer: #{answer_and_explanation}" }
      answer = answer_and_explanation["answer"]
      # Skip if the answer is blank or a validation response
      next if answer.blank? || VALIDATION_RESPONSES.include?(answer.to_s.downcase)

      # Update the model field with the answer
      update_model_field(model, question, answer, answer_and_explanation)
    end

    # Validate all documents and mark the model as validated
    all_docs_valid = validate_all_docs(model)
    model.mark_as_validated(all_docs_valid)
  end

  private

  # Update the model field with the answer
  def update_model_field(model, question, answer, answer_and_explanation)
    # camelize the question
    question = question.parameterize.underscore
    existing_value = if model.respond_to?(question.to_sym)
                       model.send(question.to_sym)
                     else
                       model.properties[question]
                     end
    update_field(model, question, answer, existing_value, answer_and_explanation)
  end

  # Update the model field with the answer
  def update_field(model, question, answer, existing_value, answer_and_explanation)
    question = question.parameterize.underscore
    if existing_value.blank?
      if model.respond_to?(question.to_sym)
        model.send(:"#{question}=", answer)
      else
        model.properties[question] = answer
      end
      answer_and_explanation["update"] = "Updated field #{question.to_sym}"
    else
      answer_and_explanation["update"] = "No Update to field #{question.to_sym}, Existing value = #{existing_value}, Extracted value = #{answer}"
    end
  end

  # Validate all documents by checking if the answers are not in the NO_LIST
  def validate_all_docs(model)
    model.doc_question_answers.all? do |doc_name, qna|
      Rails.logger.debug { "Validating #{doc_name}" }
      qna.all? do |question, response|
        answer = response["answer"]
        Rails.logger.debug { "Checking #{doc_name}, Question: #{question} Answer: #{answer}" }
        NO_LIST.exclude?(answer.to_s.downcase)
      end
    end
  end
end
