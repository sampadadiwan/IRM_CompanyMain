require 'docx'
require 'ruby_llm'

class TemplateTransformer
  attr_reader :mapping

  def initialize(descriptive_doc_path, context_sample, output_path: nil)
    @doc_path = descriptive_doc_path
    @context_sample = context_sample
    @output_path = output_path || descriptive_doc_path.sub('.docx', '_sablon_template.docx')
    @mapping = {}
  end

  def perform
    Rails.logger.debug "Step 1: Extracting placeholders from Word document..."
    placeholders = extract_placeholders
    if placeholders.empty?
      Rails.logger.debug "No placeholders found in document."
      return
    end
    Rails.logger.debug { "Found #{placeholders.size} placeholders: #{placeholders.join(', ')}" }

    Rails.logger.debug "Step 2: Building context schema from sample..."
    schema = ContextSchemaBuilder.new(@context_sample).build
    Rails.logger.debug { "Schema built with keys: #{schema.keys.join(', ')}" }

    Rails.logger.debug "Step 3: Calling AI for mapping intelligence..."
    @mapping = map_placeholders_with_ai(placeholders, schema)
    Rails.logger.debug { "AI Mapping complete. Mapped #{@mapping.size} fields." }

    Rails.logger.debug "Step 4: Generating Sablon template doc..."
    generate_sablon_template
    @output_path
  end

  private

  def extract_placeholders
    doc = Docx::Document.open(@doc_path)
    found = []

    doc.paragraphs.each do |p|
      # Match anything inside square brackets, potentially spanning across tags
      # although docx gem p.text combines them.
      p.text.scan(/\[([^\]]+)\]/m).each do |match|
        found << match.first.strip
      end
    end
    found.uniq
  end

  def map_placeholders_with_ai(placeholders, schema)
    chat = RubyLLM.chat(model: ENV.fetch("DEFAULT_MODEL", nil))
    system_msg = build_system_msg(schema)
    user_msg = "PLACEHOLDERS FOUND IN DOCUMENT: #{placeholders.join(', ')}"

    full_prompt = [system_msg, user_msg].join("\n\n")
    Rails.logger.debug "--- AI PROMPT START ---"
    Rails.logger.debug full_prompt
    Rails.logger.debug "--- AI PROMPT END ---"

    raw_response = chat.ask(full_prompt)
    parse_json(raw_response)
  rescue StandardError => e
    Rails.logger.debug { "AI Mapping Error: #{e.message}" }
    Rails.logger.error "AI Mapping Failed: #{e.message}"
    {}
  end

  def build_system_msg(schema)
    <<~SYS
      You are a legal document automation expert. I have a Word document with descriptive placeholders in square brackets.
      I need to map these to a specific Ruby data schema used by the Sablon gem for document generation.

      AVAILABLE DATA SCHEMA (JSON):
      #{schema.to_json}

      SABLON SYNTAX REFERENCE:
      - Basic Field: «=object.attribute»
      - Conditionals:
        * Start: «expression:if»
        * Else: «expression:else»
        * End: «expression:endIf»
        * Example: «capital_commitment.is_gp?:if» (renders if truthy)
      - Loops:
        * Start: «collection:each(item)»
        * End: «collection:endEach»
        * Use `item.attribute` inside the loop.
      - Nesting: Loops and conditionals can be nested. Use proper scoping.
      - Predicates: You can use Ruby methods like `.present?`, `.empty?`, `.any?`, or custom methods in conditionals.
        Example: «capital_commitment.account_entries.any?:if»

      DATA TYPES & LOGIC:
      - Collections: If a schema value is an Array `[...]`, it's a collection. Use Loops.
      - Booleans/Presence: Use Conditionals for boolean fields or when checking if an optional field exists.
      - Strings/Numbers/Dates: Use Basic Fields for direct insertion.

      TASK:
      Create a JSON mapping where the key is the placeholder text (without brackets) and the value is the Sablon expression.
      For simple fields, use dot notation like 'capital_commitment.investor_name'. Do not wrap them in delimiters; the system will wrap them in «= » automatically.
      If a placeholder implies a conditional block (e.g. [If GP...]), use the Sablon conditional syntax.
      If a placeholder implies a list (e.g. [List of payments...]), use the Sablon loop syntax.
      If a placeholder looks like an image or signature, map it to a key; the template generation will handle image syntax.

      Respond ONLY with valid JSON. No markdown fences.

      VALIDATION RULE:
      Only map to fields that exist in the AVAILABLE DATA SCHEMA.
      If a placeholder cannot be mapped to a real attribute or method, leave it as the original placeholder text or map it to a generic 'comment' field.
      DO NOT hallucinate fields like 'fund.xxx' if 'xxx' is not in the schema for 'fund'.
    SYS
  end

  def parse_json(obj)
    case obj
    when String
      begin
        # strip accidental fences if any
        cleaned = obj.strip
        cleaned = cleaned.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
        JSON.parse(cleaned)
      rescue JSON::ParserError
        {}
      end
    when Hash
      obj
    when ->(o) { o.respond_to?(:content) }
      # Handle RubyLLM::Message or similar
      content = obj.content
      text = content.respond_to?(:text) ? content.text : content
      parse_json(text)
    else
      {}
    end
  end

  def generate_sablon_template
    # We use a lower-level approach to replace text to preserve formatting
    # Sablon uses {{key}} or Mail Merge fields. Here we use the {{key}} syntax.

    # Create a copy for the template
    FileUtils.cp(@doc_path, @output_path)

    # NOTE: docx gem can be sensitive to some Word XML features.
    # If the file is complex, we use a slightly more robust way to open it.
    begin
      # Some Word docs are zipped with features that rubyzip/docx gem
      # struggle with during inflation if not handled carefully.
      # Instead of using FileUtils.cp and then Docx::Document.open(@output_path),
      # we open the source and let docx gem handle it.
      # However, docx gem sometimes has issues with specific Word zip formats.
      doc = Docx::Document.open(@doc_path)
    rescue Zip::DecompressionError => e
      Rails.logger.debug { "Initial docx open failed with decompression error: #{e.message}" }
      fixed_path = "#{@doc_path}_fixed.docx"
      Rails.logger.debug "Attempting to fix ZIP structure of source using command line..."
      system("zip -FF #{@doc_path} --out #{fixed_path}")
      doc = Docx::Document.open(fixed_path)
      FileUtils.rm_f(fixed_path)
    rescue StandardError => e
      Rails.logger.debug { "Initial docx open failed: #{e.message}" }
      raise e
    end

    doc.paragraphs.each do |p|
      @mapping.each do |original, replacement|
        # Check for presence before attempting expensive text manipulation
        if p.text.include?("[#{original}]")
          # p.text= in docx gem tries to clear existing runs and add a new one.
          # This is generally safer for simple replacements.
          # If the replacement already has Sablon delimiters or is a block tag, don't wrap in «= »
          # Sablon block tags use « »
          final_replacement = if replacement.include?("{{") || replacement.include?("«")
                                replacement
                              else
                                "«=#{replacement}»"
                              end
          new_text = p.text.gsub("[#{original}]", final_replacement)
          p.text = new_text
        end
      rescue StandardError => e
        Rails.logger.debug { "Error replacing '#{original}' in paragraph: #{e.message}" }
      end
    end

    # Explicitly clear any @output_path if it exists to avoid zip merging issues
    FileUtils.rm_f(@output_path)
    doc.save(@output_path)
  rescue StandardError => e
    Rails.logger.debug { "Fatal error in generate_sablon_template: #{e.message}" }
    Rails.logger.debug e.backtrace.first(10).join("\n")
    raise e
  end
end
