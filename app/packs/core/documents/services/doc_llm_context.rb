require 'pragmatic_segmenter'
require 'zip'
require 'nokogiri'
require 'roo'
require "ruby_llm"
class DocLlmContext < DocLlmBase
  include LlmResponseParser

  step :init
  step :populate_context_with_data
  step :setup_llm_instructions
  step :extract_data
  step :cleanup
  left :handle_errors

  # Initializes the RubyLLM chat client using the entity's API keys.
  # @param ctx [Hash] Trailblazer context hash
  # @param model [ApplicationRecord] the record whose entity provides LLM configuration

  def init(ctx, model:, **)
    # Initialize RubyLLM chat with configured model
    ctx[:chat] = LlmService.ruby_llm_chat(entity: model.entity) # Pass the entity to get any custom API keys if needed
    true
  end

  def populate_context_with_data(ctx, documents:, notes:, **)
    ctx[:context] = ""
    ctx[:context] += process_documents(documents)
    ctx[:context] += process_notes(notes)
    true
  end

  def setup_llm_instructions(ctx, **)
    # Sometimes we get the llm_instructions passed in see PortfolioReportJob.generate_report_extracts & sometimes we get passed a section see PortfolioReportJob.generate_section_extracts
    ctx[:llm_instructions] ||= "#{ctx[:section].data} Format your output as json array with each point as an item in the array. The key is the index and value is the extracted info. Do not generate nested json, just one level. Do not add any \n (newlines), \t (tabs) within an array item and do not add ```json to the output."
  end

  def extract_data(ctx, chat:, **)
    # Combine instructions and context into a single prompt
    prompt = "#{ctx[:llm_instructions]}\n\n#{ctx[:context]}"

    Rails.logger.debug "########### Sending to LLM #############"
    Rails.logger.debug prompt
    Rails.logger.debug "########################"

    # Call RubyLLM chat
    raw_response = chat.ask(prompt)

    ctx[:raw_llm_output] = raw_response
    Rails.logger.debug "########### LLM Raw Output #############"
    Rails.logger.debug raw_response
    Rails.logger.debug "########################"

    # Parse the response (handles String, Hash, or RubyLLM::Message)
    parsed = parse_llm_json(raw_response)

    if parsed.blank? || !parsed.is_a?(Hash)
      Rails.logger.error { "Failed to parse valid JSON from LLM response" }
      ctx[:extracted_info] = raw_response.to_s
      return true # Still return true to allow downstream processing
    end

    extracted_info = parsed.transform_values { |v| normalize_section_value(v) }
    ctx[:extracted_info] = extracted_info.to_json

    true
  rescue StandardError => e
    Rails.logger.error "Error in extract_data: #{e.message}"
    ctx[:extracted_info] = raw_response.to_s if raw_response
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

  # Process all documents and return their content
  def process_documents(documents)
    content = ""
    documents.each do |document|
      document.file.download do |file|
        document_content = extract_document_content(document, file)
        content += document_content if document_content.present?
      end
    end
    content
  end

  # Extract content from a single document based on its type
  def extract_document_content(document, file)
    if document.pdf?
      extract_pdf_content(document, file)
    elsif document.csv?
      extract_csv_content(document, file)
    elsif document.excel?
      extract_excel_content(document, file)
    elsif document.ppt?
      extract_ppt_content(document, file)
    else
      extract_text_content(document, file)
    end
  rescue StandardError => e
    Rails.logger.warn "Error processing #{document.name}: #{e.message}"
    nil
  end

  # Extract content from PDF files
  def extract_pdf_content(document, file)
    `pdftotext #{file.path} #{file.path}.txt`
    text_content = read_file_with_encoding("#{file.path}.txt")
    "<#{document.name}>#{text_content}</#{document.name}>"
  end

  # Extract content from CSV files
  def extract_csv_content(document, file)
    text_content = read_file_with_encoding(file.path)
    "<#{document.name}> Content: #{text_content} </#{document.name}>"
  end

  # Extract content from Excel files (all sheets)
  def extract_excel_content(document, file)
    spreadsheet = Roo::Spreadsheet.open(file.path)

    excel_content = spreadsheet.sheets.map do |sheet_name|
      sheet = spreadsheet.sheet(sheet_name)
      "\n--- Sheet: #{sheet_name} ---\n#{sanitize_utf8(sheet.to_csv)}\n"
    end.join

    "<#{document.name}> Content: #{excel_content} </#{document.name}>"
  end

  # Extract content from PowerPoint files (PPTX/PPT)
  def extract_ppt_content(document, file)
    text_parts = []
    slide_number = 0

    Zip::File.open(file.path) do |zip_file|
      # Extract slide text
      slide_entries = zip_file.glob('ppt/slides/slide*.xml').sort_by do |entry|
        entry.name.match(/slide(\d+)\.xml/)[1].to_i
      end

      slide_entries.first(30).each do |entry|
        slide_number += 1
        content = entry.get_input_stream.read
        doc = Nokogiri::XML(content)
        doc.remove_namespaces!

        texts = doc.xpath('//t').map(&:text).compact_blank
        if texts.any?
          text_parts << "--- Slide #{slide_number} ---"
          text_parts << texts.join("\n")
        end
      end

      # Extract chart data if available
      chart_entries = zip_file.glob('ppt/charts/chart*.xml')
      chart_entries.first(10).each_with_index do |entry, idx|
        chart_content = entry.get_input_stream.read
        chart_doc = Nokogiri::XML(chart_content)
        chart_doc.remove_namespaces!

        # Extract numeric values from charts
        values = chart_doc.xpath('//val').map(&:text).compact_blank
        if values.any?
          text_parts << "--- Chart #{idx + 1} Data ---"
          text_parts << values.join(", ")
        end
      end
    end

    ppt_content = text_parts.join("\n\n")
    ppt_content = "No text content found in PowerPoint" if ppt_content.blank?

    "<#{document.name}> Content: #{sanitize_utf8(ppt_content)} </#{document.name}>"
  rescue StandardError => e
    Rails.logger.warn "Error extracting PowerPoint #{document.name}: #{e.message}"
    "<#{document.name}> Content: Error extracting PowerPoint content </#{document.name}>"
  end

  # Extract content from other text-based files
  def extract_text_content(document, file)
    text_content = read_file_with_encoding(file.path)
    "<#{document.name}> Content: #{text_content} </#{document.name}>"
  end

  # Process all notes and return their content
  def process_notes(notes)
    notes.map do |note|
      note_content = sanitize_utf8(note.details.to_plain_text.to_s)
      "<Note> Content: #{note_content} Tags: #{note.tags} Created: #{note.created_at} </Note>"
    end.join
  end

  # Read file with automatic encoding detection and conversion to UTF-8
  # Handles files in various encodings (UTF-8, ISO-8859-1, Windows-1252, etc.)
  def read_file_with_encoding(file_path)
    # First, try reading as binary to detect encoding
    content = File.binread(file_path)

    # Try to detect the encoding and convert to UTF-8
    # Common encodings to try in order of likelihood
    encodings_to_try = %w[UTF-8 ISO-8859-1 Windows-1252 ASCII-8BIT]

    encodings_to_try.each do |encoding|
      # Try to force encode from the detected encoding to UTF-8
      decoded = content.force_encoding(encoding)
      if decoded.valid_encoding?
        # Successfully detected encoding, now convert to UTF-8 safely
        return decoded.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').scrub('')
      end
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      # Try next encoding
      next
    end

    # If all encodings fail, force UTF-8 and clean up
    content.force_encoding('UTF-8').scrub('')
  rescue StandardError => e
    Rails.logger.warn "Error reading file #{file_path}: #{e.message}"
    '' # Return empty string on error
  end

  # Sanitize UTF-8 encoding to prevent JSON::GeneratorError
  # Removes invalid UTF-8 characters that can't be serialized
  def sanitize_utf8(text)
    return '' if text.nil?

    text.to_s
        .encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        .scrub('') # Additional safety: remove any remaining invalid sequences
  end
end
