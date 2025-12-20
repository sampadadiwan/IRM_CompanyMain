# PortfolioCompanyAssistantTools
#
# Tools for the PortfolioCompanyAssistant.
#
module PortfolioCompanyAssistantTools
  # Tool to list portfolio companies.
  class ListPortfolioCompanies < RubyLLM::Tool
    def name = "list_portfolio_companies"

    description "List all portfolio companies with optional Ransack filtering and sorting."

    param :scope, type: :string, desc: "Filter by a predefined scope", required: false,
          enum: %w[portfolio_companies not_portfolio_companies advisors rms without_investor_accesses]
    param :query, type: :object, desc: "Ransack query hash for filtering (e.g., investor_name_cont, city_eq, tag_list_cont)", required: false
    param :sort, type: :string, desc: "Sort string (e.g., 'investor_name asc')", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(scope: nil, query: {}, sort: nil)
      @assistant.list_portfolio_companies(scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to get details for a specific portfolio company.
  class GetPortfolioCompanyDetails < RubyLLM::Tool
    def name = "get_portfolio_company_details"

    description "Get detailed information about a specific portfolio company by its ID."

    param :portfolio_company_id, type: "integer", desc: "The unique ID of the portfolio company", required: true

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(portfolio_company_id:)
      @assistant.get_portfolio_company_details(portfolio_company_id: portfolio_company_id).to_json
    end
  end

  # Tool to list valuations for a portfolio company.
  class ListValuations < RubyLLM::Tool
    def name = "list_valuations"

    description "List historical valuations for a portfolio company."

    param :portfolio_company_id, type: "integer", desc: "The unique ID of the portfolio company", required: true
    param :scope, type: :string, desc: "Filter by a predefined scope", required: false,
          enum: %w[with_synthetic]
    param :query, type: :object, desc: "Ransack query hash (attributes: valuation_date, per_share_value_cents, currency, synthetic)", required: false
    param :sort, type: :string, desc: "Sort string (e.g., 'valuation_date desc')", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(portfolio_company_id:, scope: nil, query: {}, sort: nil)
      @assistant.list_valuations(portfolio_company_id: portfolio_company_id, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list portfolio investments.
  class ListPortfolioInvestments < RubyLLM::Tool
    def name = "list_portfolio_investments"

    description "List portfolio investments (buys and sells) for a portfolio company."

    param :portfolio_company_id, type: "integer", desc: "The unique ID of the portfolio company", required: true
    param :scope, type: :string, desc: "Filter by transaction type or status", required: false,
          enum: %w[buys sells conversions distributed not_distributed proforma non_proforma]
    param :query, type: :object, desc: "Ransack query hash (attributes: investment_date, amount_cents, fmv_cents, quantity, notes)", required: false
    param :sort, type: :string, desc: "Sort string (e.g., 'investment_date desc')", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(portfolio_company_id:, scope: nil, query: {}, sort: nil)
      @assistant.list_portfolio_investments(portfolio_company_id: portfolio_company_id, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list KPIs for a portfolio company.
  class ListPortfolioKpis < RubyLLM::Tool
    def name = "list_portfolio_kpis"

    description "List KPIs (Key Performance Indicators) for one or more portfolio companies."

    param :portfolio_company_ids, type: "array", desc: "Array of portfolio company IDs", required: true
    param :scope, type: :string, desc: "Filter by KPI frequency or type", required: false,
          enum: %w[actuals budgets ics monthly quarterly yearly ytd]
    param :query, type: :object, desc: "Ransack query hash (attributes: name, value, source, kpi_report_as_of)", required: false
    param :sort, type: :string, desc: "Sort string (e.g., 'name asc')", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(portfolio_company_ids:, scope: nil, query: {}, sort: nil)
      @assistant.list_portfolio_kpis(portfolio_company_ids: portfolio_company_ids, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list portfolio report extracts.
  class ListPortfolioReportExtracts < RubyLLM::Tool
    def name = "list_portfolio_report_extracts"

    description "List report extracts, summaries, or highlights for a portfolio company."

    param :portfolio_company_id, type: "integer", desc: "The unique ID of the portfolio company", required: true
    param :query, type: :object, desc: "Ransack query hash (attributes: report_date, content, category)", required: false
    param :sort, type: :string, desc: "Sort string (e.g., 'report_date desc')", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(portfolio_company_id:, query: {}, sort: nil)
      @assistant.list_portfolio_report_extracts(portfolio_company_id: portfolio_company_id, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list documents.
  class ListDocuments < RubyLLM::Tool
    def name = "list_documents"

    description "List documents associated with a portfolio company."

    param :portfolio_company_id, type: "integer", desc: "The unique ID of the portfolio company", required: true
    param :scope, type: :string, desc: "Filter by document status or type", required: false,
          enum: %w[approved not_approved template not_template sent_for_esign not_sent_for_esign signed esign_status_completed esign_status_failed esign_status_requested]
    param :query, type: :object, desc: "Ransack query hash (attributes: name, owner_tag, text, public_visibility, esign_status)", required: false
    param :sort, type: :string, desc: "Sort string (e.g., 'created_at desc')", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(portfolio_company_id:, scope: nil, query: {}, sort: nil)
      @assistant.list_documents(portfolio_company_id: portfolio_company_id, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # PlotChart for PortfolioCompanyAssistant.
  class PlotChart < BaseAssistantTools::PlotChart
    def name = "plot_chart"

    description "Generate a chart based on provided JSON data and a descriptive prompt."

    param :data, type: :string, desc: "A JSON string of the data to be plotted.", required: true
    param :prompt, type: :string, desc: "A natural language prompt describing what the chart should represent.", required: true
  end
end
