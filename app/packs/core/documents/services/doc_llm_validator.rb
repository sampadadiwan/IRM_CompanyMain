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
    super
    ctx[:doc_questions] ||= model.doc_questions.where(document_name: document.name)
    Rails.logger.debug { "Initialized Doc LLM Validator for #{model} with #{document.name}" }
    Rails.logger.debug "DocLlmValidator Error: No open ai client" if ctx[:open_ai_client].blank?
    Rails.logger.debug "DocLlmValidator Error: No doc questions" if ctx[:doc_questions].blank?
    ctx[:open_ai_client].present? && ctx[:doc_questions].present?
  end

  # Run the checks with the llm
  # checks is a list of questions to ask the llm about the document
  # Example: checks = ["Is the name $full_name ?", "Is there a date of birth", "What is the PAN number?", "Is the pan number $PAN ?"]
  def run_checks_with_llm(ctx, model:, doc_questions:, open_ai_client:, **)
    # Replace the variables in the checks with the actual values from the kyc
    new_checks = VariableInterpolation.replace_variables(doc_questions, model)
    Rails.logger.debug { "Running checks with LLM: #{new_checks}" }

    messages = new_checks.map { |check| { type: "text", text: check } } + [
      { type: "text", text: "Return the answers to all the questions as a json document without any formatting or enclosing tags and only if it is present in the image presented to you. In the json document returned, create the key as specified by the Response Format Hint and the value is a json with answer to the specific Question and explanation for the answer. Example {'The question that was input': {answer: 'Your answer', explanation: 'Your explanation for the answer given', question_type: 'Extraction, Validation or General question'}} " },
      { type: "image_url",
        image_url: {
          url: ImageService.encode_image(ctx[:image_path])
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
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    Rails.logger.error { "Error in running checks with LLM: #{e.message}" }
    false
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
    if model.respond_to?(question.to_sym)
      existing_value = model.send(question.to_sym)
      update_field(model, question, answer, existing_value, answer_and_explanation)
    else
      existing_value = model.properties[question]
      update_field(model.properties, question, answer, existing_value, answer_and_explanation)
    end
  end

  # Update the target field with the answer
  def update_field(target, question, answer, existing_value, answer_and_explanation)
    if existing_value.blank?
      target.send(:"#{question}=", answer)
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
