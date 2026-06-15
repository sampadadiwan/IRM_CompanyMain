# frozen_string_literal: true

# Searches the current user's prior Customer Support Agent conversations for relevant context.
# Scoped to the analyst's own messages only — cannot see other users' conversations.
#
# @see FmCsChatProvider
class SearchPastMessagesTool < RubyLLM::Tool
  description "Search your previous support conversations for relevant context. " \
              "Use when the user references a past question or when you need to check " \
              "if a similar issue was already resolved."

  param :keywords,
        type: :string,
        desc: 'Space-separated search keywords (e.g. "capital call error")',
        required: true

  MAX_RESULTS = 10

  # @param analyst_id [Integer] the current user's id
  # @param support_agent_id [Integer] the current CS agent's id
  def initialize(analyst_id:, support_agent_id:)
    super()
    @analyst_id = analyst_id
    @support_agent_id = support_agent_id
  end

  # @param keywords [String] space-separated search terms
  # @return [String] matching past messages or a no-results message
  def execute(keywords:)
    terms = keywords.to_s.strip.split(/\s+/).reject(&:blank?)
    return "Please provide at least one search keyword." if terms.empty?

    messages = find_messages(terms)

    return "No previous conversations found matching: #{keywords}" if messages.empty?

    format_messages(messages, terms)
  end

  private

  # @param terms [Array<String>]
  # @return [Array<AgentChatMessage>]
  def find_messages(terms)
    conditions = terms.map { "agent_chat_messages.content LIKE ?" }
    values = terms.map { |t| "%#{sanitize_like(t)}%" }

    AgentChatMessage
      .joins(:agent_chat_session)
      .where(agent_chat_sessions: { analyst_id: @analyst_id, support_agent_id: @support_agent_id })
      .where(conditions.join(" OR "), *values)
      .order(created_at: :desc)
      .limit(MAX_RESULTS)
  end

  # @param term [String]
  # @return [String] escaped for LIKE
  def sanitize_like(term)
    term.gsub(/[%_\\]/) { |m| "\\#{m}" }
  end

  # @param messages [Array<AgentChatMessage>]
  # @param terms [Array<String>]
  # @return [String] formatted results for the LLM
  def format_messages(messages, terms)
    lines = ["Found #{messages.size} past message(s) matching: #{terms.join(', ')}\n"]

    messages.each_with_index do |msg, idx|
      timestamp = msg.created_at.strftime("%d %b %Y %H:%M")
      lines << "--- #{idx + 1}. [#{msg.role}] #{timestamp} ---"
      lines << msg.content.truncate(500)
      lines << ""
    end

    lines.join("\n")
  end
end
