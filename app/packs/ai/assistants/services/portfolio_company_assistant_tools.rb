# PortfolioCompanyAssistantTools
#
# Tools for the PortfolioCompanyAssistant.
# These tools use the @data_manager which is pre-configured with the portfolio_company.
#
module PortfolioCompanyAssistantTools
  # Tool to get a high-level snapshot of the portfolio company.
  class GetPortfolioCompanySnapshot < RubyLLM::Tool
    def name = "get_portfolio_company_snapshot"

    description "Get a high-level summary of the company including total invested, FMV, multiples (TVPI, RVPI), and latest valuation."

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute
      @data_manager.get_portfolio_company_snapshot.to_json
    end
  end

  # Tool to get details for the portfolio company.
  class GetPortfolioCompanyDetails < RubyLLM::Tool
    def name = "get_portfolio_company_details"

    description "Get detailed information about the portfolio company."

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute
      @data_manager.get_portfolio_company_details.to_json
    end
  end

  # Tool to list valuations for the portfolio company.
  class ListValuations < RubyLLM::Tool
    def name = "list_valuations"

    description "List valuations for the portfolio company. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: valuation_date, per_share_value_cents, currency, synthetic. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'top', 'latest', or 'largest' requests. Example: sort: 'valuation_date desc', limit: 10. (Maps to Ransack `s`)"
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'with_synthetic'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { currency_eq: 'USD' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'valuation_date desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_valuations(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list portfolio investments.
  class ListPortfolioInvestments < RubyLLM::Tool
    def name = "list_portfolio_investments"

    description "List portfolio investments (buys and sells) for the portfolio company. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: investment_date, amount_cents, fmv_cents, gain_cents, quantity, notes, startup, proforma. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'top', 'latest', or 'largest' requests. Example: sort: 'investment_date desc', limit: 10. (Maps to Ransack `s`)"
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'buys', 'sells', 'conversions', 'distributed', 'not_distributed', 'proforma', 'non_proforma'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { notes_cont: 'initial' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'investment_date desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      return { error: "At least one filter (scope, query, or aggregate) must be provided for list_portfolio_investments for this company as the dataset is too large." }.to_json if scope.blank? && (query.blank? || query.values.all?(&:blank?)) && aggregate.blank?

      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_portfolio_investments(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list KPIs for the portfolio company.
  class ListPortfolioKpis < RubyLLM::Tool
    def name = "list_portfolio_kpis"

    description "List KPIs for the portfolio company. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: name, value, source. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'name asc', limit: 10."
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'actuals', 'budgets', 'ics', 'monthly', 'quarterly', 'yearly', 'ytd'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Revenue', kpi_report_as_of_gteq: '2023-01-01' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'name asc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      return { error: "At least one filter (scope, query, or aggregate) must be provided for list_portfolio_kpis for this company as the dataset is too large." }.to_json if scope.blank? && (query.blank? || query.values.all?(&:blank?)) && aggregate.blank?

      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_portfolio_kpis(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list fund ratios (performance metrics).
  class ListFundRatios < RubyLLM::Tool
    def name = "list_fund_ratios"

    description "List fund ratios (performance metrics) for the portfolio company, with optional Ransack filtering, ordering, and limiting. " \
                "Attributes: name, value, end_date, latest. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'end_date desc', limit: 10. (Maps to Ransack `s`)"
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_eq: 'TVPI', latest_eq: true }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'end_date desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      return { error: "A query filter or aggregate must be provided for list_fund_ratios for this company as the dataset is too large." }.to_json if (query.blank? || query.values.all?(&:blank?)) && aggregate.blank?

      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_fund_ratios(query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list documents.
  class ListDocuments < RubyLLM::Tool
    def name = "list_documents"

    description "List documents associated with the portfolio company. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: name, owner_tag, text, public_visibility, esign_status. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'created_at desc', limit: 10."
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'approved', 'not_approved', 'template', 'not_template', 'sent_for_esign', 'not_sent_for_esign', 'signed', 'esign_status_completed', 'esign_status_failed', 'esign_status_requested'", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Agreement' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'created_at desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(scope: nil, query: {}, sort: nil, limit: nil)
      @data_manager.list_documents(scope: scope, query: query || {}, sort: sort, limit: limit).to_json
    end
  end

  # Tool to get details for a specific document.
  class GetDocument < RubyLLM::Tool
    def name = "get_document"

    description "Get detailed information and full text content for a specific document by ID or name."
    param :document_id, type: "integer", desc: "The ID of the document", required: false
    param :name, type: "string", desc: "The name of the document (can be partial)", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(document_id: nil, name: nil)
      @data_manager.get_document(document_id: document_id, name: name).to_json
    end
  end

  # Tool to analyze one or more documents using RubyLLM.
  class AnalyzeDocument < RubyLLM::Tool
    def name = "analyze_document"

    description "Analyze one or more documents to answer specific questions, perform extraction, or summarize content. " \
                "Pass a list of document IDs or names and a clear natural language prompt. " \
                "If the document is large, be specific about what information you are looking for."
    param :document_ids, type: "array", desc: "List of document IDs to analyze", required: false
    param :document_names, type: "array", desc: "List of document names (can be partial) to analyze", required: false
    param :prompt, type: "string", desc: "Natural language instructions or question for the analysis", required: true

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(prompt:, document_ids: [], document_names: [])
      @data_manager.analyze_documents(prompt: prompt, document_ids: document_ids, document_names: document_names).to_json
    end
  end

  # Tool to get cap table for the portfolio company.
  class GetCapTable < RubyLLM::Tool
    def name = "get_cap_table"

    description "Get the cap table for the portfolio company. " \
                "Optionally filter by funding rounds and group by a specific field."
    param :funding_rounds, type: "array", desc: "Optional list of funding rounds to filter by", required: false
    param :group_by_field, type: "string", desc: "Field to group by (default: 'investor_name')", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(funding_rounds: nil, group_by_field: :investor_name)
      @data_manager.get_cap_table(
        funding_rounds: funding_rounds,
        group_by_field: group_by_field
      ).to_json
    end
  end

  # Tool to get investments in cap table for the portfolio company.
  class GetInvestmentsInCapTable < RubyLLM::Tool
    def name = "get_investments_in_cap_table"

    description "Get detailed list of investments in cap table for the portfolio company. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: investor_name, category, investment_type, funding_round, investment_date, quantity, amount_cents. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Examples: sort: 'investment_date desc', limit: 10."
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'investment_date desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(query: {}, sort: nil, limit: nil)
      @data_manager.get_investments_in_cap_table(
        query: query || {},
        sort: sort,
        limit: limit
      ).to_json
    end
  end

  # PlotChart for PortfolioCompanyAssistant.
  class PlotChart < BaseAssistantTools::PlotChart
    description "Generates an interactive Chart.js chart (HTML) from a dataset and a prompt describing the desired visualization. Use this when the user asks for a graph, plot, or chart."
    def name = "plot_chart"
    param :data, type: :string, desc: "A JSON string of the data to be plotted.", required: true
    param :prompt, type: :string, desc: "A natural language prompt describing what the chart should represent.", required: true
  end

  # PlotChartFromQuery for PortfolioCompanyAssistant.
  class PlotChartFromQuery < BaseAssistantTools::PlotChartFromQuery
    description "Generates an interactive Chart.js chart (HTML) from a query and a prompt describing the desired visualization. Use this when the user asks for a graph, plot, or chart."
    def name = "plot_chart_from_query"

    param :resource, type: :string, desc: "The resource to fetch data from (e.g. 'valuations', 'kpis', 'investments').", required: true
    param :prompt, type: :string, desc: "A natural language prompt describing what data to fetch and how to plot it.", required: true
  end
end
