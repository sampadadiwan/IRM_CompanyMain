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
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'due_date desc', limit: 5."
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'approved', 'unapproved', 'completed', 'incomplete'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on (e.g., 'call_amount', 'collected_amount')", required: false
    param :group_by_field, type: :string, desc: "Field to group results by (e.g., 'status')", required: false
    param :query, type: :object, desc: "Ransack query hash.", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'due_date desc'. (Maps to Ransack `s`)", required: false
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

      @data_manager.list_capital_calls(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list capital commitments for the current fund.
  class ListSpecificFundCapitalCommitments < RubyLLM::Tool
    def name = "list_capital_commitments"
    description "List capital commitments for the current fund. " \
                "Attributes for query: folio_id, commitment_date, fund_close, investor_name, onboarding_completed, unit_type, committed_amount, collected_amount, call_amount, distribution_amount. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'committed_amount_cents desc, commitment_date desc'."
    param :folio_ids, type: "array",  desc: "Filter by folio IDs", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'lp_onboarding_complete', 'lp_onboarding_incomplete'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on (e.g., 'committed_amount', 'collected_amount', 'call_amount', 'distribution_amount')", required: false
    param :group_by_field, type: :string, desc: "Field to group results by (e.g., 'investor_name', 'unit_type')", required: false
    param :query, type: :object, desc: "Ransack query hash.", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'commitment_date desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

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
    param :folio_ids, type: "array",  desc: "Filter by folio IDs", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'paid', 'unpaid', 'pending', 'verified', 'unverified'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on (e.g., 'call_amount', 'due_amount', 'collected_amount')", required: false
    param :group_by_field, type: :string, desc: "Field to group results by (e.g., 'investor_name', 'status', 'folio_id')", required: false
    param :query, type: :object, desc: "Ransack query hash.", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

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
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'distribution_date desc', limit: 5."
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'approved', 'unapproved', 'completed', 'incomplete'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on (e.g., 'gross_amount', 'income', 'reinvestment')", required: false
    param :group_by_field, type: :string, desc: "Field to group results by (e.g., 'title', 'approved')", required: false
    param :query, type: :object, desc: "Ransack query hash.", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'distribution_date desc'. (Maps to Ransack `s`) ", required: false
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

      @data_manager.list_capital_distributions(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list payments for capital remittances in the current fund.
  class ListSpecificFundCapitalRemittancePayments < RubyLLM::Tool
    def name = "list_capital_remittance_payments"
    description "List capital remittance payments for the current fund. " \
                "Attributes for query: status payment_date, reference_no, amount, folio_amount, tracking_amount. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'payment_date desc', limit: 10."
    param :folio_ids, type: "array",  desc: "Filter by folio IDs", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'approved', 'unapproved'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on (e.g., 'amount')", required: false
    param :group_by_field, type: :string, desc: "Field to group results by (e.g., 'payment_date')", required: false
    param :query, type: :object, desc: "Ransack query hash.", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_capital_remittance_payments(folio_ids: folio_ids, scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list payments received from capital distributions for the current fund.
  class ListSpecificFundCapitalDistributionPayments < RubyLLM::Tool
    def name = "list_capital_distribution_payments"
    description "List capital distribution payments for the current fund. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'payment_date desc', limit: 10."
    param :folio_ids, type: "array",  desc: "Filter by folio IDs", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'completed', 'incomplete', 'notification_sent', 'notification_not_sent'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on (e.g., 'net_payable', 'gross_payable')", required: false
    param :group_by_field, type: :string, desc: "Field to group results by (e.g., 'payment_date', 'investor_name')", required: false
    param :query, type: :object, desc: "Ransack query hash.", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      return { error: "At least one filter (folio_ids or scope) or aggregate must be provided for list_capital_distribution_payments for this fund as the dataset is too large." }.to_json if folio_ids.blank? && scope.blank? && aggregate.blank?

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
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'buys', 'sells', 'conversions', 'distributed', 'not_distributed', 'proforma', 'non_proforma'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on (e.g., 'amount', 'fmv', 'gain')", required: false
    param :group_by_field, type: :string, desc: "Field to group results by (e.g., 'status', 'portfolio_company_name')", required: false
    param :query, type: :object, desc: "Ransack query hash.", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'investment_date desc'. (Maps to Ransack `s`) ", required: false
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

      @data_manager.list_portfolio_investments(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list fund ratios for the current fund.
  class ListSpecificFundRatios < RubyLLM::Tool
    def name = "list_fund_ratios"
    description "List performance metrics (ratios) for the current fund. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency."
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'latest'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on (e.g., 'value')", required: false
    param :group_by_field, type: :string, desc: "Field to group results by (e.g., 'name')", required: false
    param :query, type: :object, desc: "Ransack query hash.", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'end_date desc'. (Maps to Ransack `s`) ", required: false
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

      @data_manager.list_fund_ratios(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list account entries for the current fund.
  class ListSpecificFundAccountEntries < RubyLLM::Tool
    def name = "list_account_entries"
    description "List account entries for the current fund (ALWAYS aggregated). This tool ONLY returns aggregated data (sum, count, group_by). Individual records are never returned. Aggregation is mandatory. " \
                "Attributes for filtering/grouping: name, entry_type, reporting_date, period, folio_id, amount, cumulative, generated, rule_for. " \
                "Ordering: Use `sort` for grouped results. Example: aggregate: 'group_by', group_by_field: 'entry_type', aggregate_field: 'amount', sort: 'total_cents desc'."
    param :folio_ids, type: "array", desc: "Filter by folio IDs", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'cumulative', 'not_cumulative', 'generated', 'fund_entries', 'reporting', 'accounting', 'for_folios', 'for_portfolio_investments', 'for_portfolio_companies'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on. Defaults to 'amount'.", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string for results.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'. Defaults to 'sum'.", required: false

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
