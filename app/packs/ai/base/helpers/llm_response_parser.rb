# Helper module for parsing JSON responses from LLM services
# Handles different response formats: String, Hash, RubyLLM::Message
module LlmResponseParser
  # Parse JSON from LLM response
  # Handles strings (stripping markdown fences), Hashes, and RubyLLM::Message objects
  #
  # @param obj [String, Hash, RubyLLM::Message, nil] The response object from the LLM
  # @return [Hash, nil] Parsed JSON hash or nil if parsing fails
  def parse_llm_json(obj)
    case obj
    when String
      parse_json_string(obj)
    when Hash
      obj
    when RubyLLM::Message
      # Recursively call with the text content
      parse_llm_json(obj.content)
    when nil
      nil
    end
  end

  private

  # Parse a JSON string, stripping markdown code fences if present
  # @param str [String] The JSON string to parse
  # @return [Hash, nil] Parsed JSON hash or nil if parsing fails
  def parse_json_string(str)
    # Strip accidental markdown fences if any
    cleaned = str.strip
    cleaned = cleaned.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
    JSON.parse(cleaned)
  rescue JSON::ParserError
    nil
  end
end
