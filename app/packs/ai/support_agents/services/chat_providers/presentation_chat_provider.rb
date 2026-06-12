# frozen_string_literal: true

# Chat provider for PresentationAnalystAgent.
#
# Loads the latest SupportAgentReport.json_fields (period_records +
# cross_period_flags) as system-prompt context so the GP can ask follow-up
# questions about any presentation, period, commitment, or risk without having
# to re-run the agent.
#
# Reuses the shared _chat_panel.html.erb + SupportAgentChatsController — no new
# controller or view needed. Wired up in BaseChatProvider.resolve.
#
# PRD §4.4 — Chat Q&A Mode, §12.3 PresentationChatProvider.
class PresentationChatProvider < BaseChatProvider
  # System prompt injected at the start of every chat session.
  # Provides identity, date, data scope, and rendering instructions.
  def system_prompt
    Rails.logger.info { "[PresentationChatProvider] system_prompt for agent ##{support_agent.id} — #{company_name}" }

    <<~PROMPT
      You are an investor presentation analyst for #{company_name}.
      Agent: #{support_agent.name}
      User:  #{analyst&.name || 'Unknown'}
      Date:  #{Date.current.strftime('%d %b %Y')}

      You have extracted intelligence from #{period_count} investor presentation(s)
      covering #{period_range}. Your job is to answer questions about what management
      said across those presentations — commitments, risks, metrics, objectives,
      initiatives, and tone.

      RESPONSE RULES:
      - Always cite the source period inline: [Q3 2025]
      - Never fabricate. If the data doesn't contain the answer, say so explicitly.
      - Use HTML tables for metric comparisons (never markdown tables).
      - Numbers from the documents are authoritative; do not guess or interpolate.
      - When comparing across periods, highlight what changed, not just what exists.

      #{strict_scope_prompt}
      #{chart_rendering_prompt}
      #{table_rendering_prompt}

      === EXTRACTED INTELLIGENCE ===
      #{intelligence_context}
    PROMPT
  end

  # Returns an empty string — context is injected directly into system_prompt above.
  # BaseChatProvider#build_context is called by GenericChatAgent; returning "" avoids
  # duplicating the intelligence block in the conversation.
  def build_context
    ""
  end

  # SearchPresentationTextTool lets the LLM search the raw extracted JSON when the
  # GP asks for a specific quote or phrasing not surfaced in the structured flags.
  # PRD §12.4 — SearchPresentationTextTool.
  def tools
    [SearchPresentationTextTool.new(report: latest_report)]
  end

  private

  # Fetches the most recent SupportAgentReport for this agent + portfolio company.
  # The report's json_fields contain period_records and cross_period_flags.
  def latest_report
    @latest_report ||= SupportAgentReport
                       .where(support_agent: support_agent, owner_type: "Investor")
                       .order(created_at: :desc)
                       .first
  end

  # Builds the intelligence context block injected into the system prompt.
  # Format: one section per period record (oldest → newest), followed by the
  # cross-period flags summary.
  def intelligence_context
    return "No presentation data available — run the PresentationAnalystAgent first." unless latest_report

    fields  = latest_report.json_fields || {}
    records = fields["period_records"] || []
    flags   = fields["cross_period_flags"] || {}

    return "Agent has been run but no presentation documents were found or extracted." if records.empty?

    # Period records: one labelled section per period so the LLM can cite correctly
    parts = records.map do |record|
      period_label = record["period_label"]
      # Remove metadata keys that are redundant in context (already in the header)
      data = record.except("period_label", "as_of")
      "--- #{period_label} ---\n#{JSON.pretty_generate(data)}"
    end

    # Append cross-period flags as a separate section so the LLM knows what changed
    parts << "--- Cross-Period Flags ---\n#{JSON.pretty_generate(flags)}" if flags.any?

    parts.join("\n\n")
  end

  # Resolves the portfolio company name from the report's owner (an Investor record).
  def company_name
    latest_report&.owner&.investor_name || support_agent.name
  end

  # Number of period records successfully extracted in the latest run.
  def period_count
    latest_report&.json_fields&.dig("period_records")&.size || 0
  end

  # Human-readable period range shown in the system prompt header.
  # e.g. "Q1-01-25-Actual to Q4-10-25-Actual"
  def period_range
    periods = latest_report&.json_fields&.dig("periods_analyzed") || []
    return "no periods analyzed" if periods.empty?

    periods.size == 1 ? periods.first : "#{periods.first} to #{periods.last}"
  end
end
