class DocLlmContext < DocLlmBase
  step :init
  step :populate_context_with_data
  step :setup_llm_instructions
  step :extract_data
  step :cleanup
  left :handle_errors

  def populate_context_with_data(ctx, documents:, notes:, **)
    ctx[:context] = ""

    documents.each do |document|
      # Download the document
      document.file.download do |file|
        # Convert the file to HTML and concat it to the context
        # `pdftohtml -s -noframes #{file.path} #{file.path}.html`
        `pdftotext #{file.path} #{file.path}.txt`
        ctx[:context] += "<#{document.name}>" + File.read("#{file.path}.txt") + "</#{document.name}>"
      end
    end

    notes.each do |note|
      # Contact the notes to the context, but only the details, tags and created_at
      ctx[:context] += "<Note> Content: #{note.details.to_plain_text} Tags: #{note.tags} Created: #{note.created_at} </Note>"
    end

    true
  end

  def setup_llm_instructions(ctx, **)
    # Sometimes we get the llm_instructions passed in see PerfolioReportJob.generate_report_extracts & sometimes we get passed a section see PortfolioReportJob.generate_section_extracts
    ctx[:llm_instructions] ||= "#{ctx[:section].data} Format your output as json array with each point as an item in the array. The key is the index and value is the extracted info. Do not generate nested json, just one level. Do not add any \n (newlines), \t (tabs) within an array item and do not add ```json to the output."
  end

  def extract_data(ctx, open_ai_client:, **)
    messages = [
      { type: "text", text: ctx[:llm_instructions] },
      { type: "text", text: ctx[:context] }
    ]

    Rails.logger.debug "###########Sending to LLM#############"
    Rails.logger.debug messages
    Rails.logger.debug "########################"

    # Run the checks with the llm
    response = open_ai_client.chat(
      parameters: {
        model: "gpt-4o", # Required.
        response_format: { type: "json_object" },
        messages: [{ role: "user", content: messages }] # Required.
      }
    )

    # Get the results from the response
    ctx[:extracted_info] = response.dig("choices", 0, "message", "content")
    Rails.logger.debug ctx[:extracted_info]
    true
  end
end
