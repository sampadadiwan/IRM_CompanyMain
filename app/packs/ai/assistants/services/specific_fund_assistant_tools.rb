# SpecificFundAssistantTools
#
# A namespace for specialized tool definitions for SpecificFundAssistant.
# These tools remove the `fund_id` parameter where possible since it's hardcoded in the data manager.
#
class SpecificFundAssistantTools < FundAssistantTools
  # Tool to retrieve detailed information about the current fund.
  class GetSpecificFundDetails < RubyLLM::Tool
    def name = "get_fund_details"
    description "Get details of the current fund, including aggregate metrics like committed amount, collected amount, call amount, and distribution amount."

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(**_kwargs)
      @data_manager.get_fund_details.to_json
    end
  end

  # Tool to list capital calls for the current fund.
  class ListSpecificFundCapitalCalls < RubyLLM::Tool
    def name = "list_capital_calls"
    description "List capital calls for the current fund, with optional Ransack filtering, ordering, limiting and aggregation. " \
                "Attributes: name, due_date, approved, call_date, status, verified, call_amount, collected_amount, percentage_called. " \
                "There is no `scope` filter for capital calls (CapitalCall has no named scopes) -- use `query`, " \
                "e.g. { approved_eq: true }, { status_eq: 'Overdue' }. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'due_date desc', limit: 5."
    parameter :aggregate_field, type: :string, description: "Field to perform sum or group_by on (e.g., 'call_amount', 'collected_amount')", required: false
    parameter :group_by_field, type: :string, description: "Field to group results by (e.g., 'status')", required: false
    parameter :query, type: :object, description: "Ransack query hash.", required: false
    parameter :sort, type: :string, description: "Optional sort string, e.g. 'due_date desc'. (Maps to Ransack `s`)", required: false
    parameter :limit, type: :integer, description: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    parameter :aggregate, type: :string, description: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      # No `scope:` forwarded -- CapitalCall has no named scopes, and
      # FundAssistantDataManager#list_capital_calls now hard-errors on any non-blank scope
      # (see that method's comment) rather than silently ignoring one, so this tool must not
      # advertise or pass through a capability that doesn't exist.
      @data_manager.list_capital_calls(query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list capital commitments for the current fund.
  class ListSpecificFundCapitalCommitments < RubyLLM::Tool
    def name = "list_capital_commitments"
    description "List capital commitments for the current fund. " \
                "Attributes for query: folio_id, commitment_date, fund_close, investor_name, onboarding_completed, unit_type, committed_amount, collected_amount, call_amount, distribution_amount. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'committed_amount_cents desc, commitment_date desc'."
    parameter :folio_ids, type: "array", description: "Filter by folio IDs", required: false
    parameter :scope, type: :string, description: "Filter by a predefined scope. Available scopes: 'lp_onboarding_complete', 'lp_onboarding_incomplete'", required: false
    parameter :aggregate_field, type: :string, description: "Field to perform sum or group_by on (e.g., 'committed_amount', 'collected_amount', 'call_amount', 'distribution_amount')", required: false
    parameter :group_by_field, type: :string, description: "Field to group results by (e.g., 'investor_name', 'unit_type')", required: false
    parameter :query, type: :object, description: "Ransack query hash.", required: false
    parameter :sort, type: :string, description: "Optional sort string, e.g. 'commitment_date desc'. (Maps to Ransack `s`) ", required: false
    parameter :limit, type: :integer, description: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    parameter :aggregate, type: :string, description: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_capital_commitments(folio_ids: folio_ids, scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list capital remittances for the current fund.
  class ListSpecificFundCapitalRemittances < RubyLLM::Tool
    def name = "list_capital_remittances"
    description "List capital remittances for the current fund. " \
                "Attributes for query: folio_id, investor_name, payment_date, remittance_date, call_amount, collected_amount." \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'payment_date desc', limit: 10."
    parameter :folio_ids, type: "array", description: "Filter by folio IDs", required: false
    parameter :scope, type: :string, description: "Filter by a predefined scope. Available scopes: 'paid', 'unpaid', 'pending', 'verified', 'unverified'", required: false
    parameter :aggregate_field, type: :string, description: "Field to perform sum or group_by on (e.g., 'call_amount', 'due_amount', 'collected_amount')", required: false
    parameter :group_by_field, type: :string, description: "Field to group results by (e.g., 'investor_name', 'status', 'folio_id')", required: false
    parameter :query, type: :object, description: "Ransack query hash.", required: false
    parameter :sort, type: :string, description: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`) ", required: false
    parameter :limit, type: :integer, description: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    parameter :aggregate, type: :string, description: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      return { error: "At least one filter (folio_ids, scope, or query) or aggregate must be provided for list_capital_remittances for this fund as the dataset is too large." }.to_json if folio_ids.blank? && scope.blank? && (query.blank? || query.values.all?(&:blank?)) && aggregate.blank?

      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_capital_remittances(folio_ids: folio_ids, scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list capital distributions for the current fund.
  class ListSpecificFundCapitalDistributions < RubyLLM::Tool
    def name = "list_capital_distributions"
    description "List capital distributions for the current fund, with optional Ransack filtering, ordering, limiting and aggregation. " \
                "Attributes: title, distribution_date, approved, completed, distribution_on, gross_amount, income, reinvestment. " \
                "There is no `scope` filter for capital distributions (CapitalDistribution has no named scopes) -- use `query`, " \
                "e.g. { approved_eq: true }, { completed_eq: true }. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'distribution_date desc', limit: 5."
    parameter :aggregate_field, type: :string, description: "Field to perform sum or group_by on (e.g., 'gross_amount', 'income', 'reinvestment')", required: false
    parameter :group_by_field, type: :string, description: "Field to group results by (e.g., 'title', 'approved')", required: false
    parameter :query, type: :object, description: "Ransack query hash.", required: false
    parameter :sort, type: :string, description: "Optional sort string, e.g. 'distribution_date desc'. (Maps to Ransack `s`) ", required: false
    parameter :limit, type: :integer, description: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    parameter :aggregate, type: :string, description: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      # No `scope:` forwarded -- see ListSpecificFundCapitalCalls above for why.
      @data_manager.list_capital_distributions(query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list payments for capital remittances in the current fund.
  class ListSpecificFundCapitalRemittancePayments < RubyLLM::Tool
    def name = "list_capital_remittance_payments"
    description "List capital remittance payments for the current fund. " \
                "Attributes for query: status payment_date, reference_no, amount, folio_amount, tracking_amount. " \
                "There is no `scope` filter for remittance payments (CapitalRemittancePayment has no named scopes) -- use `query` instead. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'payment_date desc', limit: 10."
    parameter :folio_ids, type: "array", description: "Filter by folio IDs", required: false
    parameter :aggregate_field, type: :string, description: "Field to perform sum or group_by on (e.g., 'amount')", required: false
    parameter :group_by_field, type: :string, description: "Field to group results by (e.g., 'payment_date')", required: false
    parameter :query, type: :object, description: "Ransack query hash.", required: false
    parameter :sort, type: :string, description: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`) ", required: false
    parameter :limit, type: :integer, description: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    parameter :aggregate, type: :string, description: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_ids: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      # No `scope:` forwarded -- see ListSpecificFundCapitalCalls above for why.
      @data_manager.list_capital_remittance_payments(folio_ids: folio_ids, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list payments received from capital distributions for the current fund.
  class ListSpecificFundCapitalDistributionPayments < RubyLLM::Tool
    def name = "list_capital_distribution_payments"
    description "List capital distribution payments for the current fund. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'payment_date desc', limit: 10."
    parameter :folio_ids, type: "array", description: "Filter by folio IDs", required: false
    parameter :scope, type: :string, description: "Filter by a predefined scope. Available scopes: 'completed', 'incomplete', 'notification_sent', 'notification_not_sent'", required: false
    parameter :aggregate_field, type: :string, description: "Field to perform sum or group_by on (e.g., 'net_payable', 'gross_payable')", required: false
    parameter :group_by_field, type: :string, description: "Field to group results by (e.g., 'payment_date', 'investor_name')", required: false
    parameter :query, type: :object, description: "Ransack query hash.", required: false
    parameter :sort, type: :string, description: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`) ", required: false
    parameter :limit, type: :integer, description: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    parameter :aggregate, type: :string, description: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      # `query` was missing from this guard -- a request scoped only via a Ransack query
      # (no folio_ids/scope) was incorrectly rejected even though it did supply a real filter.
      return { error: "At least one filter (folio_ids, scope, or query) or aggregate must be provided for list_capital_distribution_payments for this fund as the dataset is too large." }.to_json if folio_ids.blank? && scope.blank? && (query.blank? || query.values.all?(&:blank?)) && aggregate.blank?

      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_capital_distribution_payments(folio_ids: folio_ids, scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list portfolio investments for the current fund.
  class ListSpecificFundPortfolioInvestments < RubyLLM::Tool
    def name = "list_portfolio_investments"
    description "List portfolio investments for the current fund. " \
                "Attributes: portfolio_company_name, status, investment_date, amount, fmv, gain, sector. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency."
    parameter :scope, type: :string, description: "Filter by a predefined scope. Available scopes: 'buys', 'sells', 'conversions', 'distributed', 'not_distributed', 'proforma', 'non_proforma'", required: false
    parameter :aggregate_field, type: :string, description: "Field to perform sum or group_by on (e.g., 'amount', 'fmv', 'gain')", required: false
    parameter :group_by_field, type: :string, description: "Field to group results by (e.g., 'status', 'portfolio_company_name')", required: false
    parameter :query, type: :object, description: "Ransack query hash.", required: false
    parameter :sort, type: :string, description: "Optional sort string, e.g. 'investment_date desc'. (Maps to Ransack `s`) ", required: false
    parameter :limit, type: :integer, description: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    parameter :aggregate, type: :string, description: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_portfolio_investments(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list fund ratios for the current fund.
  class ListSpecificFundRatios < RubyLLM::Tool
    def name = "list_fund_ratios"
    description "List performance metrics (ratios) for the current fund. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency."
    parameter :scope, type: :string, description: "Filter by a predefined scope. Available scopes: 'latest'", required: false
    parameter :aggregate_field, type: :string, description: "Field to perform sum or group_by on (e.g., 'value')", required: false
    parameter :group_by_field, type: :string, description: "Field to group results by (e.g., 'name')", required: false
    parameter :query, type: :object, description: "Ransack query hash.", required: false
    parameter :sort, type: :string, description: "Optional sort string, e.g. 'end_date desc'. (Maps to Ransack `s`) ", required: false
    parameter :limit, type: :integer, description: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    parameter :aggregate, type: :string, description: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_fund_ratios(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list account entries for the current fund.
  class ListSpecificFundAccountEntries < RubyLLM::Tool
    def name = "list_account_entries"
    description "List account entries for the current fund (ALWAYS aggregated). This tool ONLY returns aggregated data (sum, count, group_by). Individual records are never returned. Aggregation is mandatory. " \
                "Attributes for filtering/grouping: name, entry_type, reporting_date, period, folio_id, amount, cumulative, generated, rule_for. " \
                "Ordering: Use `sort` for grouped results. Example: aggregate: 'group_by', group_by_field: 'entry_type', aggregate_field: 'amount', sort: 'total_cents desc'."
    parameter :folio_ids, type: "array", description: "Filter by folio IDs", required: false
    parameter :scope, type: :string, description: "Filter by a predefined scope. Available scopes: 'cumulative', 'not_cumulative', 'generated', 'fund_entries', 'reporting', 'accounting', 'for_folios', 'for_portfolio_investments', 'for_portfolio_companies'", required: false
    parameter :aggregate_field, type: :string, description: "Field to perform sum or group_by on. Defaults to 'amount'.", required: false
    parameter :group_by_field, type: :string, description: "Field to group results by", required: false
    parameter :query, type: :object, description: "Ransack query hash", required: false
    parameter :sort, type: :string, description: "Optional sort string for results.", required: false
    parameter :aggregate, type: :string, description: "Perform an aggregation: 'count', 'sum', 'group_by'. Defaults to 'sum'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      raise "Aggregation is MANDATORY for list_account_entries. Provide `aggregate` ('sum', 'count', or 'group_by') and appropriate `aggregate_field`." if aggregate.blank?

      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_account_entries(folio_ids: folio_ids, scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # PlotChart is inherited from BaseAssistantTools
  class PlotChart < BaseAssistantTools::PlotChart
    def name = "plot_chart"
  end

  # PlotChartFromQuery is inherited from BaseAssistantTools
  class PlotChartFromQuery < BaseAssistantTools::PlotChartFromQuery
    def name = "plot_chart_from_query"
  end
end
