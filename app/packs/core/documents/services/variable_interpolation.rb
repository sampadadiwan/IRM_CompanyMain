class VariableInterpolation
  # # Usage
  # input_string = "Is the name in the document $full_name and the PAN number $pan_number?"
  # variables = extract_variables(input_string)
  # puts variables
  # Output:
  # ["full_name", "pan_number"]
  def self.extract_variables(text)
    # This will return an array of variable names without the '$'
    text.scan(/\$(\w+)/).flatten
  end

  # Replace the variables in the checks with the actual values from the kyc
  def self.replace_variables(doc_questions, model)
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
end
