class ReportPrompt
  EXAMPLES_MAP = [
    { input: "verified xxx", output: "xxx?q[c][0][a][0][name]=verified&q[c][0][p]=eq&q[c][0][v][0][value]=true&button" },
    { input: "unverified xxx", output: "xxx?q[c][0][a][0][name]=verified&q[c][0][p]=eq&q[c][0][v][0][value]=false&button" },
    { input: "verified investors created after 01/01/2020", output: "xxx?q[c][0][a][0][name]=verified&q[c][0][p]=eq&q[c][0][v][0][value]=true&q[c][1][a][0][name]=created_at&q[c][1][p]=gt&q[c][1][v][0][value]=01/01/2020" },
    { input: "xxx with investing entity containing 'Singh'", output: "xxx?q[c][1][a][0][name]=full_name&q[c][1][p]=cont&q[c][1][v][0][value]=Singh" },
    { input: "xxx with name containing 'Singh'", output: "xxx?q[c][1][a][0][name]=full_name&q[c][1][p]=cont&q[c][1][v][0][value]=Singh" }
  ].freeze

  # This method is used to translate a natural language query into a report url
  # query: The natural language query
  # model_class: The model class for which the report url is to be generated
  def self.generate_report_url(query, model_class, run_prompt: true)
    # Use few shot prompt template to generate a report url
    prompt = Langchain::Prompt::FewShotPromptTemplate.new(
      # The prefix is the text should contain the model class and the searchable attributes
      prefix: "The #{model_class} has the following searchable attributes #{all_ransackable_attributes(model_class)}. Generate a report url for the given query without outputting assumptions and explanations. Also replace terms like today with todays actual date which is #{Time.zone.today}.",
      suffix: "Input: {query}\nOutput:",
      example_prompt: Langchain::Prompt::PromptTemplate.new(
        input_variables: %w[input output],
        template: "Input: {input}\nOutput: {output}"
      ),
      examples: EXAMPLES_MAP,
      input_variables: ["query"]
    )

    # Replace the model class in the prompt template so the URL gets created properly
    llm_prompt = prompt.format(query:).gsub("xxx", model_class.to_s.underscore.pluralize)

    if run_prompt
      @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"])
      llm_response = @llm.chat(messages: [{ role: "user", content: llm_prompt }]).completion
      Rails.logger.debug "#########################"
      Rails.logger.debug llm_response.sub(/^Output:\s*/, '/')
      Rails.logger.debug "#########################"
      response = llm_response.sub(/^Output:\s*/, '/')

      response += "&no_folders=true" if model_class == Document
      response
    else
      llm_prompt
    end
  end

  def self.all_ransackable_attributes(model_class)
    ras = model_class.ransackable_attributes
    model_class.ransackable_associations.each do |assoc|
      ras << model_class.reflect_on_association(assoc.to_sym).klass.ransackable_attributes.map { |ra| "#{assoc}_#{ra}" }
    end
    ras
  end
end
