# Reads one document for a set of checks: sends the AI the document's image and each check's look-for
# text and tip, and returns what it read keyed by check id. It never sees the record — no record value is
# ever put in the prompt, and nothing in a look-for or tip is evaluated. The AI only reads; DocChecks::Judge
# decides what each value means.
#
#   result = DocChecks::DocumentReader.call(document:, checks:)
#   result.success? => result[:readings] # { "c41" => { "value" => "IN303622", "found" => true, "explanation" => "…" } }
#   result.failure? => result[:failure]  # :no_llm (the run can't run) | :unreadable_file | :unreadable_reply
#   raises DocChecks::Error::ProviderError when the AI service fails (the run can't run)
#
# See openspec/changes/document-checks/design.md (card ⑤ Reader). Worked examples H3, X1, X2, X5.
module DocChecks
  class DocumentReader < DocLlmBase
    LLM_TIMEOUT = 120.seconds

    INSTRUCTIONS = <<~TEXT.freeze
      You are reading one document image. For each item below, look only at the document.
      Reply with a single JSON object and nothing else — no markdown, no code fences.
      Use exactly the item keys given (for example "c12"). For each key give:
        {"value": "<the value as printed on the document, or yes / no for a question>",
         "found": true or false,
         "explanation": "<one short sentence: where on the document you found it, or why not>"}
      If an item is not on the document, give "found": false and "value": "".
      Items:
    TEXT

    step :init
    step :convert_file_to_image
    step :read_with_llm
    step :parse
    step :cleanup
    left :cleanup_after_failure

    # The provider and model come from the same settings the old validator used. A missing or unsupported
    # provider means the check can't run at all.
    def init(ctx, **)
      ready = super(ctx, provider: ENV.fetch("DOCUMENT_VALIDATION_PROVIDER", "openai").presence || "openai",
                         llm_model: ENV.fetch("DOCUMENT_VALIDATION_MODEL", "gpt-4o").presence || "gpt-4o", temperature: 0.1)
      ctx[:failure] = :no_llm unless ready
      ready
    rescue ArgumentError, KeyError => e
      Rails.logger.error("DocChecks::DocumentReader: no AI client (#{e.message})")
      ctx[:failure] = :no_llm
      false
    end

    # PDFs and images become one PNG; anything else (a .doc) can't be read. Worked example X1.
    def convert_file_to_image(ctx, document:, **)
      # A folder of its own per read: cleanup deletes the folder, and two reads of one document can overlap
      folder_path = "tmp/doc_checks/#{document.id}-#{SecureRandom.hex(6)}"
      converted = DocUtils.convert_file_to_image(ctx, document:, folder_path:)
      return true if converted && ctx[:image_path] && File.exist?(ctx[:image_path])

      ctx[:failure] = :unreadable_file
      false
    rescue StandardError => e
      Rails.logger.warn("DocChecks::DocumentReader: can't convert document #{document.id} (#{e.class}: #{e.message})")
      ctx[:failure] = :unreadable_file
      false
    end

    # One AI call for all of this document's checks. Any failure of the call itself is the provider's,
    # not the document's: raise so the run stops without storing results. Worked example X3.
    def read_with_llm(ctx, checks:, llm_client:, **)
      prompt = self.class.prompt_for(checks)
      image = Base64.strict_encode64(File.binread(ctx[:image_path]))
      ctx[:reply] = Timeout.timeout(LLM_TIMEOUT) do
        self.class.llm_call(client: llm_client, provider: ctx[:provider].to_s, model: ctx[:llm_model], prompt:, image:)
      end
      true
    rescue StandardError => e
      cleanup(ctx)
      raise Error::ProviderError, provider_message(e)
    end

    # Keep only the keys of this document's checks; a key the AI left out reads as not found.
    # A reply that isn't a JSON object is the document's problem. Worked example X2.
    def parse(ctx, checks:, **)
      json = JSON.parse(self.class.strip_fences(ctx[:reply].to_s))
      raise JSON::ParserError, "not an object" unless json.is_a?(Hash)

      ctx[:readings] = checks.to_h { |check| [check.reply_key, self.class.reading(json[check.reply_key])] }
      true
    rescue JSON::ParserError
      Rails.logger.warn("DocChecks::DocumentReader: unreadable reply for document #{ctx[:document]&.id}")
      Rails.logger.debug { "DocChecks::DocumentReader reply: #{ctx[:reply].to_s.first(200)}" }
      ctx[:failure] = :unreadable_reply
      false
    end

    def cleanup_after_failure(ctx, **)
      cleanup(ctx)
      true
    end

    class << self
      # The prompt: fixed instructions plus one line per check. Look-fors and tips are inserted as plain
      # text — there is no placeholder processing. Worked example X5.
      def prompt_for(checks)
        lines = checks.map do |check|
          ask = check.question? ? "answer yes or no" : "read the value"
          tip = check.tip.present? ? " Tip: #{check.tip}" : ""
          %(#{check.reply_key} (#{ask}): #{check.look_for}.#{tip})
        end
        INSTRUCTIONS + lines.join("\n")
      end

      # The single seam to the AI provider (replaced by the Cucumber fake). Returns the reply text.
      def llm_call(client:, provider:, model:, prompt:, image:)
        # Each provider wants the image in its own message shape
        response = case provider
                   when "gemini"
                     client.chat(messages: [{ role: "user", parts: [{ text: prompt }, { inline_data: { mime_type: "image/png", data: image } }] }],
                                 model:, generation_config: { response_mime_type: "application/json" })
                   when "anthropic"
                     client.chat(messages: [{ role: "user", content: [
                                   { type: "image", source: { type: "base64", media_type: "image/png", data: image } },
                                   { type: "text", text: prompt }
                                 ] }], model:, max_tokens: 4096)
                   else
                     client.chat(messages: [{ role: "user", content: [
                                   { type: "text", text: prompt },
                                   { type: "image_url", image_url: { url: "data:image/png;base64,#{image}" } }
                                 ] }], model:, response_format: { type: "json_object" })
                   end
        completion_text(response)
      end

      def completion_text(response)
        if response.respond_to?(:chat_completion) && response.chat_completion.present?
          response.chat_completion
        elsif response.respond_to?(:raw_response) && response.raw_response.is_a?(Hash) && response.raw_response["candidates"]
          response.raw_response["candidates"].first&.dig("content", "parts")&.pluck("text")&.join("\n")
        else
          response.completion
        end
      end

      def strip_fences(text)
        text.strip.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
      end

      # Normalise one entry of the reply: {"value" => String, "found" => Boolean, "explanation" => String}
      def reading(entry)
        case entry
        when Hash
          value = entry["value"].is_a?(String) ? entry["value"].strip : entry["value"]&.to_s
          found = entry.key?("found") ? ActiveModel::Type::Boolean.new.cast(entry["found"]) == true : value.present?
          { "value" => value.to_s, "found" => found && value.present?, "explanation" => entry["explanation"].to_s }
        when String, Numeric
          { "value" => entry.to_s.strip, "found" => entry.to_s.strip.present?, "explanation" => "" }
        else
          { "value" => "", "found" => false, "explanation" => "" }
        end
      end
    end

    private

    # A message users can see: never the provider's raw error text
    def provider_message(error)
      text = "#{error.class} #{error.message}"
      Rails.logger.error("DocChecks::DocumentReader: AI call failed (#{text.first(300)})")
      if text.match?(/429|rate.?limit|too many/i)
        "the AI service is busy"
      else
        "the AI service is unavailable"
      end
    end
  end
end
