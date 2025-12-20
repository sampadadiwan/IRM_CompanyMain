# PortfolioCompanyAssistantTools
#
# Tools for the PortfolioCompanyAssistant.
#
module PortfolioCompanyAssistantTools
  # Tool to list portfolio companies.
  class ListPortfolioCompanies < RubyLLM::Tool
    def name = "list_portfolio_companies"

    description "List all portfolio companies with optional Ransack filtering. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: investor_name, city, tag_list. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'investor_name asc' or query: { s: 'investor_name desc' }."
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'portfolio_companies', 'not_portfolio_companies', 'advisors', 'rms', 'without_investor_accesses'", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { investor_name_cont: 'Venture', tag_list_cont: 'Tech' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'investor_name asc'. (Maps to Ransack `s`)", required: false

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

    description "Get detailed information about a specific portfolio company."
    param :portfolio_company_id, type: "integer", desc: "The ID of the portfolio company", required: true

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

    description "List valuations for a portfolio company. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: valuation_date, per_share_value_cents, currency, synthetic. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'valuation_date desc'."
    param :portfolio_company_id, type: "integer", desc: "The ID of the portfolio company", required: true
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'with_synthetic'", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { currency_eq: 'USD' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'valuation_date desc'. (Maps to Ransack `s`)", required: false

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

    description "List portfolio investments (buys and sells) for a portfolio company. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: investment_date, amount_cents, fmv_cents, gain_cents, quantity, notes, startup, proforma. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'investment_date desc'."
    param :portfolio_company_id, type: "integer", desc: "The ID of the portfolio company", required: true
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'buys', 'sells', 'conversions', 'distributed', 'not_distributed', 'proforma', 'non_proforma'", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { notes_cont: 'initial' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'investment_date desc'. (Maps to Ransack `s`)", required: false

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

    description "List KPIs for one or more portfolio companies. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: name, value, source. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'name asc'."
    param :portfolio_company_ids, type: "array", desc: "The IDs of the portfolio companies", required: true
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'actuals', 'budgets', 'ics', 'monthly', 'quarterly', 'yearly', 'ytd'", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Revenue', kpi_report_as_of_gteq: '2023-01-01' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'name asc'. (Maps to Ransack `s`)", required: false

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

    description "List portfolio report extracts (summaries/highlights) for a portfolio company. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: report_date, content, category. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'report_date desc'."
    param :portfolio_company_id, type: "integer", desc: "The ID of the portfolio company", required: true
    param :query, type: :object, desc: "Ransack query hash, e.g. { content_cont: 'growth' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'report_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(portfolio_company_id:, query: {}, sort: nil)
      @assistant.list_portfolio_report_extracts(portfolio_company_id: portfolio_company_id, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list fund ratios (performance metrics).
  class ListFundRatios < RubyLLM::Tool
    def name = "list_fund_ratios"

    description "List fund ratios (performance metrics), with optional Ransack filtering and ordering. " \
                "Attributes: name, value, owner_type, owner_id, end_date, latest. " \
                "You can also filter by portfolio_company_id. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'end_date desc'."
    param :portfolio_company_id, type: "integer", desc: "The ID of the portfolio company", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_eq: 'TVPI', latest_eq: true }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'end_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(portfolio_company_id: nil, query: {}, sort: nil)
      @assistant.list_fund_ratios(portfolio_company_id: portfolio_company_id, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list documents.
  class ListDocuments < RubyLLM::Tool
    def name = "list_documents"

    description "List documents associated with a portfolio company. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: name, owner_tag, text, public_visibility, esign_status. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'created_at desc'."
    param :portfolio_company_id, type: "integer", desc: "The ID of the portfolio company", required: true
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'approved', 'not_approved', 'template', 'not_template', 'sent_for_esign', 'not_sent_for_esign', 'signed', 'esign_status_completed', 'esign_status_failed', 'esign_status_requested'", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Agreement' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'created_at desc'. (Maps to Ransack `s`)", required: false

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

    param :data, type: :string, desc: "A JSON string of the data to be plotted.", required: true
    param :prompt, type: :string, desc: "A natural language prompt describing what the chart should represent.", required: true
  end
end
