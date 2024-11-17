class AiPolars
  EXAMPLES_MAP = [
    { input: "sum amount_cents, filter by entry type 'Fees' and group by fund_id, unit_type and entry_type", output: 'df.filter(Polars.col("entry_type") == "Fees").group_by([:fund_id, :unit_type, :entry_type]).agg(Polars.col(:amount_cents).sum).to_a.to_json' },
    { input: "sum amount_cents, group by entry_type", output: 'df.group_by([:entry_type]).agg(Polars.col(:amount_cents).sum).to_a.to_json' },
    { input: "sum committed amount cents, group by unit_type", output: 'df.group_by([:unit_type]).agg(Polars.col(:committed_amount_cents).sum).to_a.to_json' },
    { input: "filter by entry type 'Fees'", output: 'df.filter(Polars.col("entry_type") == "Fees").to_a.to_json' },
    { input: "filter by fund name 'XYZ'", output: 'df.filter(Polars.col("fund_name") == "XYZ").to_a.to_json' }

  ].freeze

  # This method is used to translate a natural language query into a report url
  # query: The natural language query
  # model_class: The model class for which the report url is to be generated
  def self.generate_query(query, model_classes, run_prompt: true)
    # Use few shot prompt template to generate a report url

    attributes = model_classes.map do |model_class|
      "The #{model_class} has the following attributes <#{model_class}>#{model_class.new.attributes.keys.join(',')}</#{model_class}>"
    end

    prompt = Langchain::Prompt::FewShotPromptTemplate.new(
      # The prefix is the text should contain the model class and the searchable attributes
      prefix: "#{attributes.join('\n')}. Generate a ruby polars query given the examples. When selecting, grouping, filtering, use only the attributes. Do not add ```ruby or ``` to the code. Simply return only the code",
      suffix: "Input: {query}\nOutput:",
      example_prompt: Langchain::Prompt::PromptTemplate.new(
        input_variables: %w[input output],
        template: "Input: {input}\nOutput: {output}"
      ),
      examples: EXAMPLES_MAP,
      input_variables: ["query"]
    )

    # Replace the model class in the prompt template so the URL gets created properly
    llm_prompt = prompt.format(query:)

    if run_prompt
      @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"])
      llm_response = @llm.chat(messages: [{ role: "user", content: llm_prompt }]).completion
      Rails.logger.debug "#########################"
      Rails.logger.debug llm_response.sub(/^Output:\s*/, '/')
      Rails.logger.debug "#########################"
      llm_response.sub(/^Output:\s*/, '/')

    else
      llm_prompt
    end
  end

  # rubocop:disable Security/Eval
  # rubocop:disable Naming/MethodParameterName
  def self.run_query(query, model_classes, _df)
    polars_query = generate_query(query, model_classes)
    Rails.logger.debug { "Polars Query: #{polars_query}" }
    result = eval(polars_query)
    Rails.logger.debug { "Result: #{result}" }
    result
  end
  # rubocop:enable Naming/MethodParameterName
  # rubocop:enable Security/Eval
end
