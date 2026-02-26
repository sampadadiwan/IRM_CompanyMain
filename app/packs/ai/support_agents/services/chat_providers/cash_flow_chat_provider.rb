# frozen_string_literal: true

# Provides cash-flow-specific context for the chat assistant.
# Pulls the latest CashFlowAssistantAgent run results from SupportAgentReport
# json_fields and feeds them as context to the LLM.
class CashFlowChatProvider < BaseChatProvider
  # @return [String] system prompt for the cash flow chat assistant
  def system_prompt
    Rails.logger.info "[CashFlowChatProvider] system_prompt called for agent ##{support_agent.id}"

    <<~PROMPT
      You are a cash flow analysis assistant for #{support_agent.entity&.name || 'the organization'}.
      Agent: #{support_agent.name}
      User: #{analyst&.name || 'Unknown'}
      Date: #{Date.current.strftime('%d %b %Y')}

      You have access to the latest cash flow analysis results from the agent's most recent run.
      Use this data to answer questions about fund cash positions, upcoming investments,
      expenses, runway, and recommendations.

      Guidelines:
      - Be professional and concise
      - Reference specific fund names and numbers from the data
      - Format currency values clearly
      - If the data is stale or a fund was blocked, mention it
      - If you don't have data to answer a question, say so honestly

      TOOL USE — CRITICAL:
      For ANY hypothetical or "what if" question (e.g. "what if we deploy more", "what if a deal falls through",
      "what happens if we call capital"), you MUST call the cash_flow_stress_scenario tool.
      Do NOT attempt to compute scenario results manually from the context data above.

      #{strict_scope_prompt}

      #{table_rendering_prompt}

      #{chart_rendering_prompt}

    PROMPT
  end

  # @return [String] context built from SupportAgentReport json_fields
  def build_context
    reports = SupportAgentReport.where(support_agent: support_agent)
                                .where(status: :completed)
                                .where(owner_type: "Fund")
                                .order(updated_at: :desc)

    # Take up to 5 latest reports per fund (for trend analysis)
    latest_reports = reports.group_by(&:owner_id)
                            .flat_map { |_fund_id, fund_reports| fund_reports.first(5) }

    Rails.logger.info "[CashFlowChatProvider] Found #{reports.count} completed fund reports for agent ##{support_agent.id}"

    if reports.empty?
      Rails.logger.warn "[CashFlowChatProvider] No completed reports found. Falling back to no-context message."
      return "No cash flow reports available. The agent has not been run yet."
    end

    sections = latest_reports.map { |report| format_fund_report(report) }
    context = sections.join("\n\n---\n\n")

    Rails.logger.info "[CashFlowChatProvider] Context length: #{context.length} chars"
    Rails.logger.debug { "[CashFlowChatProvider] Context preview: #{context.first(500)}" }

    context
  end

  # @return [Array<CashFlowStressScenarioTool>] tools available to the chat assistant
  def tools
    [CashFlowStressScenarioTool.new(support_agent: support_agent)]
  end

  private

  # @param report [SupportAgentReport] a completed fund-level report
  # @return [String] formatted summary of the fund's cash flow data
  def format_fund_report(report)
    data = report.json_fields
    currency = data["currency"] || "USD"

    lines = []
    lines << "## Fund: #{data['fund_name'] || report.owner&.name || 'Unknown'} (Run: #{report.updated_at.strftime('%d %b %Y %H:%M')})"
    lines << "Status: #{data['fund_status'] || data['status']}"
    lines << "Last updated: #{report.updated_at.strftime('%d %b %Y %H:%M')}"
    lines << ""
    lines << "Cash Available: #{fmt(data['cash_available'], currency)}"
    lines << "Upcoming Investments: #{fmt(data['upcoming_investments'], currency)}"
    lines << "Estimated Expenses (90d): #{fmt(data['estimated_expenses'], currency)}"
    lines << "Buffer Required: #{fmt(data['buffer_required'], currency)}"
    lines << "Net Position: #{fmt(data['net_position'], currency)}"
    lines << "Runway: #{data['runway_days']} days"
    lines << "Recommended Call: #{fmt(data['recommended_call'], currency)}"

    if data["cash_breakdown"].present?
      lines << ""
      lines << "### Cash Breakdown"
      data["cash_breakdown"].each do |entry|
        lines << "- #{entry['entity_name']}: #{fmt(entry['amount_cents'], currency)} (as of #{entry['last_updated']})"
      end
    end

    if data["investment_list"].present?
      lines << ""
      lines << "### Upcoming Investments"
      data["investment_list"].each do |inv|
        lines << "- #{inv['name']} (#{inv['entity_name']}): #{fmt(inv['amount_cents'], currency)} — expected #{inv['expected_date']}"
      end
    end

    lines.join("\n")
  end

  # @param cents [Integer, nil] amount in cents
  # @param currency [String] ISO currency code
  # @return [String] formatted money string
  def fmt(cents, currency)
    return "N/A" if cents.nil?

    Money.new(cents, currency).format
  end
end
