# frozen_string_literal: true

# Parses a deal update email using an LLM to extract structured data.
#
# Takes the raw email body and returns a hash with:
#   - intent: "meeting_note", "task", or "unknown"
#   - stakeholder_string: the stakeholder name mentioned (or nil)
#   - body: cleaned note/task text
#   - due_date: ISO 8601 date string (or nil)
#   - due_date_source_text: the original date phrase from the email (or nil)
#
# Uses the existing LlmService.ruby_llm_chat interface with structured
# JSON output. The system prompt constrains the LLM to return only the
# expected schema — no freeform text.
#
# @see DealIngestProcessor for the orchestrator that calls this
# @see LlmService for the LLM client factory
class DealEmailParser
  # Default result when parsing fails or the LLM returns garbage.
  UNKNOWN_RESULT = {
    "intent" => "unknown",
    "stakeholder_string" => nil,
    "body" => nil,
    "due_date" => nil,
    "due_date_source_text" => nil,
    "assignee_string" => nil
  }.freeze

  # Parse an email body into structured deal update data.
  #
  # @param email_body [String] the raw email body (HTML or plain text)
  # @param entity [Entity] the entity for LLM API key resolution
  # @param received_at [DateTime] when the email was received (for relative date resolution)
  # @return [Hash] parsed result with intent, stakeholder_string, body, due_date, due_date_source_text
  def self.call(email_body:, entity:, received_at: Time.current)
    new(email_body:, entity:, received_at:).parse
  end

  def initialize(email_body:, entity:, received_at:)
    @email_body = email_body
    @entity = entity
    @received_at = received_at
  end

  # Run the LLM parse and return structured result.
  # Returns UNKNOWN_RESULT if the LLM call fails or returns unparseable output.
  #
  # @return [Hash]
  def parse
    return UNKNOWN_RESULT if @email_body.blank?

    cleaned = strip_html(@email_body)
    return UNKNOWN_RESULT if cleaned.blank?

    prompt = build_prompt(cleaned)
    response = call_llm(prompt)
    parse_response(response)
  rescue StandardError => e
    Rails.logger.error { "DealEmailParser: LLM call failed — #{e.message}" }
    UNKNOWN_RESULT
  end

  private

  # Strip HTML tags and decode entities to get plain text.
  #
  # @param html [String] raw HTML or plain text
  # @return [String] cleaned plain text
  def strip_html(html)
    ActionController::Base.helpers.strip_tags(html)&.squish
  end

  # Build the system + user prompt for the LLM.
  #
  # @param text [String] cleaned email body
  # @return [String]
  def build_prompt(text)
    <<~PROMPT
      You are parsing an email sent by a fund manager to update a deal board.
      Today's date is #{@received_at.strftime('%Y-%m-%d')}.

      Extract the following from the email and return ONLY valid JSON — no markdown, no explanation:

      {
        "intent": "meeting_note" or "task" or "unknown",
        "stakeholder_string": "name of the investor/stakeholder mentioned" or null,
        "body": "cleaned text for the note or task description",
        "due_date": "YYYY-MM-DD" or null,
        "due_date_source_text": "original date phrase from email" or null,
        "assignee_string": "name of the person assigned to this task" or null

      }

      Rules:
      - intent is "meeting_note" if the email describes a meeting, call, conversation, update, or observation about a stakeholder
      - intent is "task" if the email describes something that needs to be done, a follow-up, a to-do, or an action item
      - intent is "unknown" if you cannot determine the intent
      - stakeholder_string is the investor/company name mentioned — extract it exactly as written
      - If no stakeholder is mentioned, set stakeholder_string to null
      - body is the cleaned, relevant text — remove email signatures, greetings, and boilerplate
      - due_date: resolve relative dates ("next Friday", "in two weeks") relative to today's date (#{@received_at.strftime('%Y-%m-%d')})
      - due_date_source_text: the original phrase the user wrote (e.g. "by next Friday")
      - assignee_string: if the email mentions someone by name who should do the task (e.g. "Neil to follow up", "Ask Priya to send", "assign to @Khushali", "@Neil to handle"), extract their name. Look for patterns like "@Name", "Name to do X", "ask Name to", "assign to Name", "Name should", "Name will". Extract just the first name or full name — no titles, no email addresses. If no assignee is mentioned or the sender is doing it themselves, set to null.
      - assignee_string only applies when intent is "task" — set to null for meeting_note

      - If no due date is mentioned, set both due_date and due_date_source_text to null

      Email:
      #{text}
    PROMPT
  end

  # Call the LLM and return the raw response text.
  #
  # @param prompt [String] the full prompt
  # @return [String, nil] raw LLM response
  def call_llm(prompt)
    chat = LlmService.ruby_llm_chat(entity: @entity)
    response = chat.ask(prompt)
    response&.content
  end

  # Parse the LLM response into a structured hash.
  # Tries to extract JSON from the response, handling both raw JSON
  # and markdown-fenced JSON (```json ... ```).
  #
  # @param raw [String, nil] raw LLM response text
  # @return [Hash] parsed result or UNKNOWN_RESULT
  def parse_response(raw)
    return UNKNOWN_RESULT if raw.blank?

    json_match = raw.match(/```json\s*(\{.+?\})\s*```/m) ||
                 raw.match(/```\s*(\{.+?\})\s*```/m) ||
                 raw.match(/(\{.+\})/m)

    return UNKNOWN_RESULT unless json_match

    parsed = JSON.parse(json_match[1])
    validate_result(parsed)
  rescue JSON::ParserError => e
    Rails.logger.warn { "DealEmailParser: JSON parse failed — #{e.message}" }
    UNKNOWN_RESULT
  end

  # Validate and normalize the parsed result.
  # Ensures all expected keys exist and intent is valid.
  #
  # @param parsed [Hash] raw parsed JSON
  # @return [Hash] validated result
  def validate_result(parsed)
    intent = parsed["intent"]
    intent = "unknown" unless %w[meeting_note task].include?(intent)

    {
      "intent" => intent,
      "stakeholder_string" => parsed["stakeholder_string"]&.strip.presence,
      "body" => parsed["body"]&.strip.presence,
      "due_date" => parsed["due_date"]&.strip.presence,
      "due_date_source_text" => parsed["due_date_source_text"]&.strip.presence,
      "assignee_string" => parsed["assignee_string"]&.strip.presence
    }
  end
end
