# PortfolioCompanyAssistant
#
# Orchestrator for the Portfolio Company Assistant AI.
# Handles queries about a specific portfolio company's valuations, investments, KPIs, and documents.
#
class PortfolioCompanyAssistant < BaseAssistant
  DESCRIPTION = "I can help you with this portfolio company's valuations, investments, cap table, KPIs, fund ratios, and documents.".freeze
  AI_MODEL = ENV.fetch('DEFAULT_MODEL', 'gemini-3-flash-preview').freeze

  MONTHLY_REPORT_QUERIES = [
    "Provide a detailed snapshot and one-page summary of this company. Include its name, current stage, sector, profile, total invested, current FMV, and performance multiples.",
    "List the valuation history for this company. Include date, per-share value, and currency. Highlight the most recent valuation.",
    "Plot a line chart of the company's valuation vs time using all available valuation data.",
    "List all our investment transactions in this company. Include dates, amounts, quantity, and whether it was a buy or sell.",
    "Plot a chart of investment amount and FMVs for this company",
    "Show the current cap table summary for this company. Group by investor name and show ownership percentages.",
    "Plot a pie chart of the current ownership structure (cap table) by investor name.",
    "List last 24 months, monthly KPIs for this company (e.g., Revenue, EBITDA, Cash Burn). Format as a table.",
    "Show the trend for 'Revenue' and 'EBITDA' over the last 12 months using available KPI reports. Present as a table with monthly columns.",
    "Plot a line chart of monthly Revenue and EBITDA for the last 12 months.",
    "List the latest documents uploaded for this company in the last 30 days."
  ].freeze

  def initialize(user:, portfolio_company:, chat: nil)
    super(user: user, chat: chat)
    @portfolio_company = portfolio_company
    @data_manager = PortfolioCompanyAssistantDataManager.new(user: user, portfolio_company: portfolio_company)
  end

  def tools
    [
      PortfolioCompanyAssistantTools::GetPortfolioCompanySnapshot.new(@data_manager),
      PortfolioCompanyAssistantTools::GetPortfolioCompanyDetails.new(@data_manager),
      PortfolioCompanyAssistantTools::ListValuations.new(@data_manager),
      PortfolioCompanyAssistantTools::ListPortfolioInvestments.new(@data_manager),
      PortfolioCompanyAssistantTools::GetCapTable.new(@data_manager),
      PortfolioCompanyAssistantTools::GetInvestmentsInCapTable.new(@data_manager),
      PortfolioCompanyAssistantTools::ListPortfolioKpis.new(@data_manager),
      PortfolioCompanyAssistantTools::ListFundRatios.new(@data_manager),
      PortfolioCompanyAssistantTools::ListDocuments.new(@data_manager),
      PortfolioCompanyAssistantTools::GetDocument.new(@data_manager),
      PortfolioCompanyAssistantTools::AnalyzeDocument.new(@data_manager),
      PortfolioCompanyAssistantTools::PlotChart.new(self),
      PortfolioCompanyAssistantTools::PlotChartFromQuery.new(self)
    ]
  end

  def system_prompt
    <<~SYSTEM
      You are a helpful AI assistant specialized in data for a single Portfolio Company: #{@portfolio_company.investor_name}.
      You can retrieve information about this company, including its valuations, investments, KPIs, and documents.

      Hyperlinking Rules:
      - Most data objects returned by tools include a `view_link` field.
      - ALWAYS use this `view_link` to hyperlink the primary identifier (like name or ID) in your markdown tables or text.
      - DO NOT create a separate column for "view_link" or "Link". Instead, embed the link into the specific column it refers to.
      - Use an HTML anchor tag with `target="_blank"`.
      - **CRITICAL**: Table headers MUST NEVER be hyperlinked.
      - Example: `<a href="/portfolio_investments/123" target="_blank">Investment ID</a>` or `<a href="/documents/456" target="_blank">Document Name</a>`.

      You will format your responses as markdown, typically using tables for lists of data.
      Always use the provided tools to ensure accuracy.

      Guidelines:
      - You are already scoped to the portfolio company: #{@portfolio_company.investor_name} (ID: #{@portfolio_company.id}).
      - Negative Constraints:
        - NEVER fabricate data. If a tool returns no data or an error, report it accurately.
        - NEVER guess valuations or ownership percentages if not explicitly provided by tools.
        - DO NOT include internal IDs or view_links in the visible text of your response unless as a hyperlink.
      - Efficiency Rule: For any request involving totals, sums, or breakdowns (e.g., "total value", "breakdown by fund", "sum of investment"), you MUST use the `aggregate` parameter (`sum` or `group_by`). Fetching individual records to perform math is STRICTLY FORBIDDEN.
      - Mandatory Parameters for Aggregation:
        - When `aggregate` is `'sum'`, you MUST provide `aggregate_field` (the numeric field to sum).
        - When `aggregate` is `'group_by'`, you MUST provide both `aggregate_field` and `group_by_field`.
      - Use `GetPortfolioCompanySnapshot` for a high-level overview of the company's financial standing and performance.
      - Use `GetPortfolioCompanyDetails` to get basic info about this company.
      - Use `ListValuations` to see how the company's value has changed.
      - NEVER call `list_portfolio_kpis`, `list_fund_ratios`, or `list_portfolio_investments` without additional filters (scope, or a specific query). These datasets for this company are too large to retrieve unfiltered.
      - Use `ListPortfolioInvestments` to see investment transactions.
      - Use `GetCapTable` for the current ownership structure.
      - Use `ListPortfolioKpis` for financial and operational metrics.
      - **KPI Scopes & Filters**:
        - Default scope is `monthly,actuals`.
        - If the user asks for data that might be reported less frequently (like Runway, Valuations, or Year-end metrics), you MUST try other scopes if the default one returns no results.
        - Available scopes: `monthly`, `quarterly`, `yearly`, `actuals`, `budgets`.
        - If one scope fails, BROADEN your search. For example, if `monthly` Runway data is missing, check `quarterly` and `yearly`.
        - Use `all_time_eq: 'true'` in the query if you need to fetch historical data beyond the last 12 months.
      - **Optimized Charting**: To create a chart efficiently (without fetching large datasets into the chat history), you MUST use the `plot_chart_from_query` tool.
        - Provide the `resource` name (e.g., `'valuations'`), any `query` filters, and a `prompt` for the chart.
        - Use this tool whenever the user asks for a chart based on a large collection of data.
      - Fallback Charting: If you already have the data in the conversation history, you can use `plot_chart(data: '...', prompt: '...')`. However, `plot_chart_from_query` is preferred for efficiency.
      - **IMPORTANT**: When the user asks for a chart, you MUST use either the `plot_chart_from_query` or `plot_chart` tool. In your FINAL response, you MUST summarize the chart's findings.
      - **CRITICAL**: To ensure the user sees the chart, you MUST include the literal string returned by the chart tools in your response. The chart tool returns an HTML snippet (e.g., `<div class="chart-wrap">...</div>`); you must output this snippet EXACTLY as received from the tool.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
    SYSTEM
  end

  def default_report_queries
    MONTHLY_REPORT_QUERIES
  end

  private

  def find_or_create_chat
    Chat.where(
      user: @user,
      entity_id: @user.entity_id,
      assistant_type: 'PortfolioCompanyAssistant',
      model: AI_MODEL,
      owner: @portfolio_company
    ).first_or_create!(
      enable_broadcast: false,
      name: "Portfolio Company Assistant Chat (#{@portfolio_company.investor_name}) #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
    )
  end
end
