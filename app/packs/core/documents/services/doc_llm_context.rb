require 'pragmatic_segmenter'
class DocLlmContext < DocLlmBase
  step :init
  step :populate_context_with_data
  step :setup_llm_instructions
  step :extract_data
  step :cleanup
  left :handle_errors

  def init(ctx, **)
    super(ctx, provider: ENV.fetch('DOCUMENT_VALIDATION_PROVIDER', nil), llm_model: ENV.fetch('DOCUMENT_VALIDATION_MODEL', nil), temperature: 0.1, **)
  end

  def populate_context_with_data(ctx, documents:, notes:, **)
    ctx[:context] = ""

    documents.each do |document|
      # Download the document
      document.file.download do |file|
        if document.pdf?
          # Convert the file to HTML and concat it to the context
          # `pdftohtml -s -noframes #{file.path} #{file.path}.html`
          `pdftotext #{file.path} #{file.path}.txt`
          ctx[:context] += "<#{document.name}>" + File.read("#{file.path}.txt") + "</#{document.name}>"
        else
          # For CSV files, we can just read the content and add it to the context
          text_content = File.read(file.path)
          ctx[:context] += "<#{document.name}> Content: #{text_content} </#{document.name}>"
        end
      end
    end

    notes.each do |note|
      # Contact the notes to the context, but only the details, tags and created_at
      ctx[:context] += "<Note> Content: #{note.details.to_plain_text} Tags: #{note.tags} Created: #{note.created_at} </Note>"
    end

    true
  end

  def setup_llm_instructions(ctx, **)
    # Sometimes we get the llm_instructions passed in see PortfolioReportJob.generate_report_extracts & sometimes we get passed a section see PortfolioReportJob.generate_section_extracts
    ctx[:llm_instructions] ||= "#{ctx[:section].data} Format your output as json array with each point as an item in the array. The key is the index and value is the extracted info. Do not generate nested json, just one level. Do not add any \n (newlines), \t (tabs) within an array item and do not add ```json to the output."
  end

  def extract_data(ctx, llm_client:, **) # rubocop:disable Metrics/MethodLength
    messages = [
      { role: "user", parts: [{ text: ctx[:llm_instructions] }] },
      { role: "user", parts: [{ text: ctx[:context] }] }
    ]

    Rails.logger.debug "########### Sending to LLM #############"
    Rails.logger.debug messages
    Rails.logger.debug "########################"

    # Ensure the model parameter is set if not already provided
    model_name = ctx[:llm_model]

    # Configure generation parameters
    generation_config = {
      response_mime_type: 'application/json'
    }

    # Call the chat method with the correctly structured messages
    response = llm_client.chat(
      messages: messages,
      model: model_name,
      generation_config: generation_config
    )

    Rails.logger.debug response

    # Access the response content directly
    # Access the raw response and navigate to the content
    raw_response = response.raw_response
    parts = raw_response.dig("candidates", 0, "content", "parts")

    if parts.blank?
      Rails.logger.error { "Unexpected response structure: #{raw_response.inspect}" }
      return false
    end

    raw_json = parts.pluck("text").join("\n")
    ctx[:raw_llm_output] = raw_json # optional, but super helpful for debugging
    Rails.logger.debug "########### LLM Raw Output #############"
    Rails.logger.debug raw_json
    Rails.logger.debug "########################"
    begin
      parsed = JSON.parse(raw_json)
      extracted_info = parsed.transform_values { |v| normalize_section_value(v) }
      ctx[:extracted_info] = extracted_info.to_json # its stored as json and parsed in doc generator
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse JSON from LLM: #{e.message} | raw: #{raw_json.inspect}"
      ctx[:extracted_info] = raw_json
    end

    true
  end

  def normalize_section_value(value)
    case value
    when String
      # Paragraph or single line → turn into array of sentences
      split_into_points(value)
    when Array
      # Flatten & clean each item
      value.flat_map do |item|
        case item
        when String
          # If the item itself looks like a paragraph, break it up
          looks_like_paragraph?(item) ? split_into_points(item) : [clean_point(item)]
        else
          if item.respond_to?(:to_s)
            clean_point(item.to_s)
          else
            []
          end
        end
      end
    else
      value
    end
  end

  def looks_like_paragraph?(text)
    (text.length > 180 && text.count(".!?") > 2) || text.include?("\n")
  end

  def clean_point(text)
    text.to_s.strip.gsub(/\s+/, " ")
  end

  def split_into_points(text)
    segmenter = PragmaticSegmenter::Segmenter.new(text: text)
    segmenter.segment.map { |s| clean_point(s) }.compact_blank
  end
end
