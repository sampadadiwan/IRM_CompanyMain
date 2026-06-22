# SpecificFundAssistant
#
# A specialized version of FundAssistant that is locked to a single fund.
# It ensures all queries and tools are focused exclusively on that fund.
#
class SpecificFundAssistant < BaseAssistant
  DESCRIPTION = "I can help you with details, capital calls, commitments, and performance of a specific fund.".freeze
  AI_MODEL = ENV.fetch('DEFAULT_MODEL', 'gemini-3-flash-preview').freeze

  STRATEGIC_QUERIES = [
    "Provide a concise summary of this fund's profile and current status.",
    "Analyze the trend of performance ratios (XIRR, TVPI, DPI) for the last 12 months only. Use the 'query' parameter to filter by date (e.g., 'end_date_gteq') and 'sort' by date. Identify any significant improvements or declines.",
    "Plot a line chart showing the historical trend of TVPI and DPI for this fund.",
    "Examine the capital call and distribution history. Are there any unusual spikes or outliers in the last 12 months? Use the 'query' parameter to filter capital calls and distributions by date (e.g., 'due_date_gteq') to retrieve only relevant records. Analyze the 'Called vs Distributed' ratio trend.",
    "Plot a chart showing cumulative capital called vs cumulative capital distributed over the fund's lifetime.",
    "Analyze the portfolio for concentration risk. Identify the top 3 investments by FMV (use 'sort' and 'limit: 3') and calculate their percentage of the total portfolio. Are there any specific tags that are over-indexed?",
    "Plot a bar chart of the top 10 portfolio companies by FMV, highlighting any investment that represents more than 15% of the total FMV.",
    "Identify 'star' performers and 'underperformers' in the portfolio by comparing investment cost vs current FMV. List the top 3 and bottom 3 investments by gain/loss multiple. Execute two efficient queries: one sorted descending with 'limit: 3', and one sorted ascending with 'limit: 3'.",
    "Review the capital commitments. Identify any LPs with significant outstanding (pending) capital remittances. Use the 'scope' parameter (e.g., 'pending' or 'unpaid') and 'sort' by amount to find them efficiently. Is there a risk to the fund's liquidity?",
    "Based on the current cash flow trends and portfolio valuation, provide a brief analysis of the fund's trajectory towards its target returns."
  ].freeze

  OPERATIONAL_QUERIES = [
    "Identify all 'unpaid' capital remittances where the due date is in the past. Calculate the total overdue amount and group by LP. Plot a bar chart showing the overdue amount per LP.",
    "Review capital remittances created in the last 90 days. Compare the count of 'verified' vs 'unverified' records using the `aggregate: 'count'` parameter. Plot a pie chart showing the proportion of verified vs unverified remittances to assess reconciliation progress.",
    "Audit recent remittance payments (last 90 days). Identify any payments where the notification has not been sent (use `query: { payment_notification_sent_eq: false }`). Are there any unusual delays in notifying LPs of received funds?",
    "Review capital distribution payments with scope 'incomplete'. Summarize the total 'net_payable' that is yet to be paid. Plot a bar chart of the top 10 incomplete distribution payments by amount.",
    "Calculate the fund's remaining dry powder (Total Committed - Total Called). Summarize this by LP for the top 10 investors. Plot a bar chart showing 'Called Amount' vs 'Remaining Commitment' for these top investors.",
    "Examine 'verified' capital remittances from the last 6 months. Compare the 'remittance_date' (call date) vs 'payment_date' (actual receipt) to calculate the average collection lag in days. Plot a line chart showing this lag trend over time.",
    "Identify the top 5 LPs by commitment size and check if any have 'unpaid' remittances or 'incomplete' distribution payments. Provide a status table for these key stakeholders."
  ].freeze

  # Initializes the SpecificFundAssistant.
  #
  # @param user [User] The user for whom the assistant is acting.
  # @param fund [Fund] The specific fund to focus on (Mandatory).
  # @param chat [Chat, nil] Optional chat session.
  def initialize(user:, fund:, chat: nil)
    raise ArgumentError, "Fund is mandatory for SpecificFundAssistant" unless fund

    super(user: user, chat: chat)
    @fund = fund
    @data_manager = SpecificFundAssistantDataManager.new(user: user, fund: fund)
    @data_manager.assistant = self
  end

  # Returns the list of tools, specialized for the specific fund context.
  def tools
    [
      SpecificFundAssistantTools::GetSpecificFundDetails.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalCalls.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalCommitments.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalRemittances.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalDistributions.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundPortfolioInvestments.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundRatios.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalRemittancePayments.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalDistributionPayments.new(@data_manager),
      # SpecificFundAssistantTools::ListSpecificFundAccountEntries.new(@data_manager),
      SpecificFundAssistantTools::PlotChart.new(self),
      SpecificFundAssistantTools::PlotChartFromQuery.new(self)
    ]
  end

  # Custom system prompt for the specific fund context.
  def system_prompt
    <<~SYSTEM
      You are a helpful AI assistant for a Private Equity Fund Management platform, specifically assisting with the fund: **#{@fund.name}**.

      You ONLY answer questions and provide data related to **#{@fund.name}** (ID: #{@fund.id}). Do not provide information about other funds.

      You have access to tools to retrieve information and plot charts. Format responses as markdown and typically as a table when possible. Always use tools to get accurate data.

      Hyperlinking Rules:
      - Most data objects returned by tools include a `view_link` field.
      - ALWAYS use this `view_link` to hyperlink the primary identifier.
      - DO NOT create a separate column for "view_link" or "Link". Instead, embed the link into the specific column it refers to.
      - Use an HTML anchor tag with `target="_blank"`.
      - **CRITICAL**: Table headers MUST NEVER be hyperlinked.

      Tool Usage Rules:
      - All data you retrieve MUST be for **#{@fund.name}** (ID: #{@fund.id}).
      - You MUST provide the `fund_id: "#{@fund.id}"` to ALL tools when calling them.
      - Efficiency Rule: For any request involving totals, sums, or breakdowns (e.g., "total amount", "breakdown by investor", "sum of collected"), you MUST use the `aggregate` parameter (`sum` or `group_by`). Fetching individual records to perform math is STRICTLY FORBIDDEN.
      - Fees & Expenses: For any request involving "Setup Fees", "Management Fees", "Expenses", or other accounting entries, you MUST use the `list_account_entries` tool.
      - Mandatory Parameters for Aggregation:
        - When `aggregate` is `'sum'`, you MUST provide `aggregate_field` (the numeric field to sum).
        - When `aggregate` is `'group_by'`, you MUST provide both `aggregate_field` and `group_by_field`.
      - NEVER call `list_capital_remittances` or `list_capital_distribution_payments` without additional filters (folio_ids, or a specific query/scope) unless using `aggregate`. These datasets for this fund are too large to retrieve unfiltered.
      - Valid Scopes:
        - For Capital Remittances: `paid`, `unpaid`, `pending`, `verified`, `unverified`.
        - For Capital Remittance Payments: Use `query` parameters like `payment_notification_sent_eq: true/false`.
        - For Capital Distribution Payments: `completed`, `incomplete`.
        - DO NOT hallucinate scopes like "unapproved". If a scope is not listed here, use `query` parameters instead.
      - **Optimized Charting**: To create a chart efficiently (without fetching large datasets into the chat history), you MUST use the `plot_chart_from_query` tool.
        - Provide the `resource` name (e.g., `'capital_remittances'`), any `query` filters, and a `prompt` for the chart.
        - Use this tool whenever the user asks for a chart based on a large collection of data.
      - Fallback Charting: If you already have the data in the conversation history, you can use `plot_chart(data: '...', prompt: '...')`. However, `plot_chart_from_query` is preferred for efficiency.
      - **IMPORTANT**: When the user asks for a chart, you MUST use either the `plot_chart_from_query` or `plot_chart` tool. In your FINAL response, you MUST summarize the chart's findings.
      - **CRITICAL**: To ensure the user sees the chart, you MUST include the literal string returned by the chart tools in your response. The chart tool returns an HTML snippet (e.g., `<div class="chart-wrap">...</div>`); you must output this snippet EXACTLY as received from the tool.
      - Never guess IDs.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
      Current Fund: #{@fund.name} (ID: #{@fund.id})
    SYSTEM
  end

  def default_report_queries
    STRATEGIC_QUERIES
  end

  # Overriding run to handle specific chart logic that was present in the original
  def run(prompt)
    response = super

    # If the response is empty but we have tool calls, it's likely a chart generation
    # where the LLM didn't provide a final summary. We'll try to find the last chart tool output.
    if (response.content.blank? || (response.content.respond_to?(:text) && response.content.text.blank?)) && @chat.messages.last&.role == "tool"
      last_tool_msg = @chat.messages.where(role: "tool").order(created_at: :desc).first
      response.content = last_tool_msg.content if last_tool_msg&.content&.include?("chart-renderer")
    end

    response
  end

  private

  def find_or_create_chat
    Chat.where(
      user: @user,
      entity_id: @user.entity_id,
      owner: @fund,
      assistant_type: 'SpecificFundAssistant'
    ).first_or_create!(
      model: AI_MODEL,
      enable_broadcast: false,
      name: "#{@fund.name} #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
    )
  end
end
