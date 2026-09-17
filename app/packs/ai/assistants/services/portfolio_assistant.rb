# PortfolioAssistant
#
# Orchestrator for the Portfolio Assistant AI.
# Handles queries about valuations, investments, KPIs, and documents.
#
class PortfolioAssistant < BaseAssistant
  DESCRIPTION = "I can help you with portfolio companies, valuations, investments, cap tables, KPIs, fund ratios, and documents.".freeze
  AI_MODEL = ENV.fetch('DEFAULT_MODEL', 'gemini-3-flash-preview').freeze

  # Unlike PortfolioCompanyAssistant, this assistant previously had no default_report_queries
  # override, so scheduling a report against it via AssistantReportJob silently ran with an
  # empty query list (inherits BaseAssistant#default_report_queries -> []) and produced nothing.
  CROSS_PORTFOLIO_REPORT_QUERIES = [
    "List all portfolio companies with their sector/tags and city. Format as a table.",
    "Show total invested and current FMV broken down by portfolio company (use the aggregate group_by feature). Format as a table sorted by total invested descending.",
    "List the most recent valuation for every portfolio company. Include valuation date, per-share value, and currency.",
    "Plot a bar chart of total invested amount by portfolio company across the whole portfolio.",
    "Show current TVPI and RVPI for every portfolio company, sorted by TVPI descending.",
    "List documents uploaded across the portfolio in the last 30 days."
  ].freeze

  def initialize(user:, chat: nil)
    super
    @data_manager = PortfolioAssistantDataManager.new(user: user)
  end

  def tools
    [
      PortfolioAssistantTools::ListPortfolioCompanies.new(@data_manager),
      PortfolioAssistantTools::GetPortfolioCompanySnapshot.new(@data_manager),
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
      - For a general "overview" or "summarize this company" question about ONE company, prefer `GetPortfolioCompanySnapshot` (total invested, current FMV, latest valuation, TVPI/RVPI in one call) over chaining several other tools together.
      - NEVER call `list_portfolio_kpis`, `list_fund_ratios`, or `list_portfolio_investments` without filters (portfolio_company_ids, fund_ids, or a specific query/scope). These datasets are too large to retrieve unfiltered.
      - **KPI Date Range Default**: `list_portfolio_kpis` defaults to the last 12 months when no date filter is given. If the user asks for a longer history (e.g. "3-year trend", "since inception", "all time"), you MUST pass `all_time_eq: 'true'` or an explicit `kpi_report_as_of_gteq` in the query -- otherwise you will silently get only 12 months of data and must NOT present it as the full history the user asked for.
      - For cap table information for a single company, use `GetCapTable`.
      - To get investment details across multiple portfolio companies (cross-company analysis), use `GetInvestmentsInCapTable`.
      - For KPIs, you can pass multiple `portfolio_company_ids` to `ListPortfolioKpis`.
      - **KPI Batching (MANDATORY)**: When asked for KPIs across multiple companies:
        1. Call `list_portfolio_companies` ONCE to get all matching company IDs. NEVER call it again in the same request.
        2. Call `list_portfolio_kpis` ONCE passing ALL company IDs together in a single call — never loop company by company or quarter by quarter.
        3. If `list_portfolio_kpis` returns empty for the requested KPI name:
           a. Call `list_portfolio_kpis` ONE more time for the same company IDs WITHOUT any name filter to discover what KPIs are available.
           b. STOP. Tell the user: "The KPI '[requested name]' is not available for these companies. Available KPIs are: [list them]."
           c. Do NOT try alternate KPI name variations. Do NOT re-fetch companies. Do NOT call any tool again.
        4. If only some companies have data, plot the chart with what is available and clearly state which companies had no data.
        5. If the user asks for "any N companies", take the first N returned by `list_portfolio_companies` — do NOT hunt for replacements if some lack data. Report what you found and stop.
        6. Call `plot_chart` ONCE with the collected data.
        Calling `list_portfolio_companies` more than once per user request is STRICTLY FORBIDDEN.
        Calling `list_portfolio_kpis` more than twice (once to fetch, once to discover available KPIs if empty) per request is STRICTLY FORBIDDEN.
      - **Optimized Charting**: For resources like `portfolio_investments`, `fund_ratios`, or `capital_calls` where you do NOT need to pre-filter by company IDs, use `plot_chart_from_query` — provide the `resource` name, any `query` filters, and a `prompt` for the chart.
        - For KPI charts, do NOT use `plot_chart_from_query`. Follow the KPI Batching rule above instead (fetch companies → fetch all KPIs in one call → plot_chart).
      - Fallback Charting: If you already have the data in the conversation history, you can use `plot_chart(data: '...', prompt: '...')`. However, `plot_chart_from_query` is preferred for efficiency.
      - **IMPORTANT**: When the user asks for a chart, you MUST use either the `plot_chart_from_query` or `plot_chart` tool. In your FINAL response, you MUST summarize the chart's findings.
      - **CRITICAL**: To ensure the user sees the chart, you MUST include the literal string returned by the chart tools in your response. The chart tool returns an HTML snippet (e.g., `<div class="chart-wrap">...</div>`); you must output this snippet EXACTLY as received from the tool.
      - Translate status or date filters into Ransack queries where appropriate.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
    SYSTEM
  end

  def default_report_queries
    CROSS_PORTFOLIO_REPORT_QUERIES
  end
end
