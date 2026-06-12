# frozen_string_literal: true

# RubyLLM tool used by PresentationChatProvider to search across extracted
# presentation text stored in SupportAgentReport.json_fields["period_records"].
#
# The GP uses this in chat when they want a specific quote, number, or phrase
# that isn't surfaced in the structured cross-period flags — e.g.:
#   "What exact wording did management use about churn in Q3?"
#   "Show me everything about the Series B across all periods."
#
# PRD §4.4 — Chat Q&A Mode, §12.4 SearchPresentationTextTool.
class SearchPresentationTextTool < RubyLLM::Tool
  description "Search extracted investor presentation text for a specific keyword, " \
              "phrase, or topic. Use when the structured flags don't contain the " \
              "exact wording or detail the user is asking about."

  # query: what to look for — matched case-insensitively across all period records
  param :query, type: :string, desc: "Keyword, phrase, or topic to search for"

  # period: optional — restrict the search to a single period label (e.g. "Q3-10-25-Actual")
  param :period,
        type: :string,
        desc: "Optional period label to restrict the search (e.g. 'Q3-10-25-Actual'). Leave blank to search all periods.",
        required: false

  def initialize(report:)
    # Hold a reference to the SupportAgentReport so execute() can access json_fields
    @report = report
    super()
  end

  def execute(query:, period: nil)
    return "No presentation data available. Run the agent first." unless @report

    records = (@report.json_fields || {}).fetch("period_records", [])

    # Narrow to a specific period when the GP specifies one
    if period.present?
      records = records.select { |r| r["period_label"].to_s.downcase.include?(period.downcase) }
      return "No records found for period '#{period}'." if records.empty?
    end

    # Split query into individual terms; match any term (OR search) for higher recall
    terms = query.downcase.split(/\s+/).first(6).compact_blank
    return "Query is blank." if terms.empty?

    # Serialise each record to JSON for full-text matching across all eight extracted fields
    matches = records.filter_map do |record|
      record_json = record.to_json.downcase
      next unless terms.any? { |term| record_json.include?(term) }

      # Return a brief excerpt of the full record so the LLM gets readable context
      "=== #{record['period_label']} ===\n#{record.to_json.truncate(1000)}"
    end

    if matches.any?
      # Cap at 3 records to avoid overflowing the LLM context with raw JSON
      matches.first(3).join("\n\n")
    else
      "No matching content found for: #{query}"
    end
  end
end
