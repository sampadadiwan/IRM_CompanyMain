# PortfolioAssistant
#
# Orchestrator for the Portfolio Assistant AI.
# Handles queries about valuations, investments, KPIs, and documents.
#
class PortfolioAssistant < BaseAssistant
  DESCRIPTION = "I can help you with portfolio companies, valuations, investments, cap tables, KPIs, fund ratios, and documents.".freeze
  AI_MODEL = ENV.fetch('DEFAULT_MODEL', 'gemini-3-flash').freeze

  def initialize(user:, chat: nil)
    super
    @data_manager = PortfolioAssistantDataManager.new(user: user)
  end

  def tools
    [
      PortfolioAssistantTools::ListPortfolioCompanies.new(@data_manager),
      PortfolioAssistantTools::GetPortfolioCompanyDetails.new(@data_manager),
      PortfolioAssistantTools::ListValuations.new(@data_manager),
      PortfolioAssistantTools::ListPortfolioInvestments.new(@data_manager),
      PortfolioAssistantTools::GetCapTable.new(@data_manager),
      PortfolioAssistantTools::GetInvestmentsInCapTable.new(@data_manager),
      PortfolioAssistantTools::ListPortfolioKpis.new(@data_manager),
      PortfolioAssistantTools::ListFundRatios.new(@data_manager),
      PortfolioAssistantTools::ListDocuments.new(@data_manager),
      PortfolioAssistantTools::GetDocument.new(@data_manager),
      PortfolioAssistantTools::AnalyzeDocument.new(@data_manager),
      PortfolioAssistantTools::PlotChart.new(self),
      PortfolioAssistantTools::PlotChartFromQuery.new(self)
    ]
  end

  def system_prompt
    <<~SYSTEM
      You are a helpful AI assistant specialized in Portfolio data for a Private Equity platform.
      You can retrieve information about portfolio companies, including their valuations, investments, KPIs, report extracts, and documents.

      Hyperlinking Rules:
      - Most data objects returned by tools include a `view_link` field.
      - ALWAYS use this `view_link` to hyperlink the primary identifier (like name or ID) in your markdown tables or text.
      - DO NOT create a separate column for "view_link" or "Link". Instead, embed the link into the specific column it refers to.
      - Use an HTML anchor tag with `target="_blank"` for these links to ensure they open in a new window.
      - **CRITICAL**: Table headers MUST NEVER be hyperlinked.
      - Example: `<a href="/investors/123" target="_blank">Portfolio Company</a>` or `<a href="/documents/456" target="_blank">Document Name</a>`.

      You will format your responses as markdown, typically using tables for lists of data.
      Always use the provided tools to ensure accuracy. Never guess IDs or data.

      Guidelines:
      - Efficiency Rule: For any request involving totals, sums, or breakdowns (e.g., "total value", "breakdown by company", "sum of investment"), you MUST use the `aggregate` parameter (`sum` or `group_by`). Fetching individual records to perform math is STRICTLY FORBIDDEN.
      - Mandatory Parameters for Aggregation:
        - When `aggregate` is `'sum'`, you MUST provide `aggregate_field` (the numeric field to sum).
        - When `aggregate` is `'group_by'`, you MUST provide both `aggregate_field` and `group_by_field`.
      - If you need to find a portfolio company, use `ListPortfolioCompanies`.
      - Once you have the `portfolio_company_id`, you can query its valuations, investments, extracts, or documents.
      - NEVER call `list_portfolio_kpis`, `list_fund_ratios`, or `list_portfolio_investments` without filters (portfolio_company_ids, fund_ids, or a specific query/scope). These datasets are too large to retrieve unfiltered.
      - For cap table information for a single company, use `GetCapTable`.
      - To get investment details across multiple portfolio companies (cross-company analysis), use `GetInvestmentsInCapTable`.
      - For KPIs, you can pass multiple `portfolio_company_ids` to `ListPortfolioKpis`.
      - **Optimized Charting**: To create a chart efficiently (without fetching large datasets into the chat history), you MUST use the `plot_chart_from_query` tool.
        - Provide the `resource` name (e.g., `'portfolio_investments'`), any `query` filters, and a `prompt` for the chart.
        - Use this tool whenever the user asks for a chart based on a large collection of data.
      - Fallback Charting: If you already have the data in the conversation history, you can use `plot_chart(data: '...', prompt: '...')`. However, `plot_chart_from_query` is preferred for efficiency.
      - **IMPORTANT**: When the user asks for a chart, you MUST use either the `plot_chart_from_query` or `plot_chart` tool. In your FINAL response, you MUST summarize the chart's findings.
      - **CRITICAL**: To ensure the user sees the chart, you MUST include the literal string returned by the chart tools in your response. The chart tool returns an HTML snippet (e.g., `<div class="chart-wrap">...</div>`); you must output this snippet EXACTLY as received from the tool.
      - Translate status or date filters into Ransack queries where appropriate.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
    SYSTEM
  end
end
