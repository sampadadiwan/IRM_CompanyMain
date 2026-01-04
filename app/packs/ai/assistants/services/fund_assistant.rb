require 'erb'

# FundAssistant
#
# The main orchestrator for the Private Equity Fund Assistant AI.
# This class configures the system prompt, initializes the data manager,
# and registers the available tools that the AI can use.
#
class FundAssistant < BaseAssistant
  DESCRIPTION = "I can help you with fund details, capital calls, commitments, remittances, distributions, portfolio investments, and fund ratios.".freeze
  AI_MODEL = ENV.fetch("DEFAULT_MODEL").freeze

  # Initializes the FundAssistant.
  #
  # @param user [User] The user for whom the assistant is acting.
  # @param chat [Chat] The chat session.
  def initialize(user:, chat: nil)
    super
    @data_manager = FundAssistantDataManager.new(user: user)
  end

  # --- Public API for Driver ---

  # Returns the list of instantiated tools available to the AI.
  #
  # @return [Array<RubyLLM::Tool>] An array of tool instances.
  def tools
    [
      FundAssistantTools::ListFunds.new(@data_manager),
      FundAssistantTools::GetFundDetails.new(@data_manager),
      FundAssistantTools::ListCapitalCalls.new(@data_manager),
      FundAssistantTools::ListCapitalCommitments.new(@data_manager),
      FundAssistantTools::ListCapitalRemittances.new(@data_manager),
      FundAssistantTools::ListCapitalDistributions.new(@data_manager),
      FundAssistantTools::ListPortfolioInvestments.new(@data_manager),
      FundAssistantTools::ListFundRatios.new(@data_manager),
      FundAssistantTools::ListCapitalRemittancePayments.new(@data_manager),
      FundAssistantTools::ListCapitalDistributionPayments.new(@data_manager),
      # FundAssistantTools::ListAccountEntries.new(@data_manager),
      FundAssistantTools::PlotChart.new(self),
      FundAssistantTools::PlotChartFromQuery.new(self)
    ]
  end

  # Generates the system prompt for the AI.
  #
  # @return [String] The system prompt.
  def system_prompt
    <<~SYSTEM
      You are a helpful AI assistant for a Private Equity Fund Management platform.
      You have access to tools to retrieve information and plot charts. You will format the response as markdown and typically as a table when possible. Always use the tools to get accurate data.

      Hyperlinking Rules:
      - Most data objects returned by tools include a `view_link` field.
      - ALWAYS use this `view_link` to hyperlink the primary identifier (like name, folio, or ID) in your markdown tables or text.
      - DO NOT create a separate column for "view_link" or "Link". Instead, embed the link into the specific column it refers to.
      - Use an HTML anchor tag with `target="_blank"` for these links to ensure they open in a new window.
      - **CRITICAL**: Table headers MUST NEVER be hyperlinked.
      - Example: `<a href="/funds/123" target="_blank">Fund Name</a>` or `<a href="/investors/456" target="_blank">Investor Name</a>`.

      Tool Usage Rules:
      - Efficiency Rule: For any request involving totals, sums, counts, or breakdowns (e.g., "how many", "total amount", "breakdown by fund", "sum of collected"), you MUST use the `aggregate` parameter.
      - Fees & Expenses: For any request involving "Setup Fees", "Management Fees", "Expenses", or other accounting entries, you MUST use the `list_account_entries` tool.
      - PROHIBITION: You are STRICTLY FORBIDDEN from fetching individual records to perform calculations in your head. For example, if a user asks "How many folios per fund", DO NOT call `list_capital_commitments` to get the rows; instead, call it with `aggregate: 'group_by'`, `group_by_field: 'fund_id'`, and `aggregate_field: 'id'`.
      - Mandatory Parameters for Aggregation:
        - When `aggregate` is `'sum'`, you MUST provide `aggregate_field` (the numeric field to sum).
        - When `aggregate` is `'group_by'`, you MUST provide both `aggregate_field` and `group_by_field`.
      - When searching for items like remittances or commitments, you can filter by `fund_id`, `folio_id`, or a Ransack `query`.
      - NEVER call `list_capital_remittances` or `list_capital_distribution_payments` without filters (fund_ids, folio_ids, or a specific query/scope). These datasets are too large to retrieve unfiltered.
      - It is NOT necessary to provide a `fund_id` if a `folio_id` or a sufficiently specific `query` is given.
      - If searching for a specific folio (e.g., "folio B103"), search directly using `folio_ids: ["B103"]` in the appropriate tool. DO NOT list all funds first unless the user specifically asks for funds.
      - NEVER call the same tool multiple times for the same folio. One call with `folio_ids` is enough to get data across all funds.
      - If the user mentions a status like "unpaid", "pending", or "overdue", translate this into a Ransack query (e.g., `{ status_not_eq: 'Paid' }`).
      - **Optimized Charting**: To create a chart efficiently (without fetching large datasets into the chat history), you MUST use the `plot_chart_from_query` tool.
        - Provide the `resource` name (e.g., `'capital_remittances'`), any `query` filters, and a `prompt` for the chart.
        - Use this tool whenever the user asks for a chart based on a large collection of data.
      - Fallback Charting: If you already have the data in the conversation history, you can use `plot_chart(data: '...', prompt: '...')`. However, `plot_chart_from_query` is preferred for efficiency.
      - **IMPORTANT**: When the user asks for a chart, you MUST use either the `plot_chart_from_query` or `plot_chart` tool. In your FINAL response, you MUST summarize the chart's findings.
      - **CRITICAL**: To ensure the user sees the chart, you MUST include the literal string returned by the chart tools in your response. The chart tool returns an HTML snippet (e.g., `<div class="chart-wrap">...</div>`); you must output this snippet EXACTLY as received from the tool.
      - Never guess IDs.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
    SYSTEM
  end
end
