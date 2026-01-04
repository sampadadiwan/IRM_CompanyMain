require 'erb'

# FundAssistantTools
#
# A namespace for all the tool definitions used by the FundAssistant.
#
class FundAssistantTools < BaseAssistantTools
  # Tool to list funds with various filters.
  class ListFunds < RubyLLM::Tool
    description "Return list all funds with the committed, collected and distribution amounts, with optional Ransack filtering, ordering, and limiting. " \
                "Hint: For totals, just use the funds data; do not compute using commitments, remittances or distributions as committed, collected, and distribution amounts are already present in the fund. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: name, currency, tracking_currency, category, tag_list, unit_types, first_close_date, last_close_date, start_date. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'top', 'largest', or 'most recent' requests. Examples: sort: 'committed_amount_cents desc', limit: 10."
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'feeder_funds', 'master_funds'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Venture', currency_eq: 'USD' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'name_asc', 'first_close_date desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @assistant.list_funds(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to retrieve detailed information about a specific fund.
  class GetFundDetails < RubyLLM::Tool
    description "Get details of a specific fund"
    param :fund_id, type: "integer", desc: "The ID of the fund", required: true

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id:)
      @assistant.get_fund_details(fund_id: fund_id).to_json
    end
  end

  # Tool to list capital calls.
  class ListCapitalCalls < RubyLLM::Tool
    description "List capital calls, with optional Ransack filtering, ordering, and limiting. " \
                "fund_ids is optional. " \
                "Attributes: name, due_date, approved, call_date, status, verified, call_amount, collected_amount, percentage_called. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'top', 'latest', or 'largest' requests. Example: sort: 'due_date desc', limit: 5."
    param :fund_ids, type: "array", desc: "List of fund IDs", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'due_date desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_ids: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @assistant.list_capital_calls(fund_ids: fund_ids, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list capital commitments.
  class ListCapitalCommitments < RubyLLM::Tool
    description "List capital commitments / Folios. Can be filtered by fund_ids, folio_ids, or a Ransack query. fund_ids and folio_ids are optional. fund_ids is not required if folio_ids is provided. At least one filter must be used. " \
                "IMPORTANT: If you need to find all commitments for a specific folio across all funds, ONLY provide the `folio_ids` parameter. DO NOT list funds first or provide `fund_ids` unless specifically requested for a subset of funds. " \
                "CRITICAL: If you find yourself calling this tool repeatedly with different fund IDs for the same folio, STOP. Call it once with `folio_ids: ['FOLIO_ID']` and NO `fund_ids` to get all data in one go. " \
                "Attributes for query: folio_id, commitment_date, fund_close, investor_name, onboarding_completed, unit_type, committed_amount, collected_amount, call_amount, distribution_amount. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'top', 'largest', or 'most recent' requests. Example: sort: 'committed_amount_cents desc', limit: 10."
    param :fund_ids, type: "array", desc: "Filter by fund IDs", required: false
    param :folio_ids, type: "array", desc: "Filter by folio IDs", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'lp_onboarding_complete', 'lp_onboarding_incomplete'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'committed_amount_cents desc, commitment_date desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @assistant.list_capital_commitments(fund_ids: fund_ids, folio_ids: folio_ids, scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list capital remittances.
  class ListCapitalRemittances < RubyLLM::Tool
    description "List capital remittances. Can be filtered by fund_ids, folio_ids, scope, or a Ransack query. fund_ids and folio_ids are optional. fund_ids is not required if folio_ids is provided. At least one filter must be used. " \
                "Attributes for query: folio_id, investor_name, payment_date, remittance_date, call_amount, collected_amount." \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'latest', 'largest', or 'top' requests. Example: sort: 'payment_date desc', limit: 10."
    param :fund_ids, type: "array", desc: "Filter by fund IDs", required: false
    param :folio_ids, type: "array", desc: "Filter by folio IDs", required: false
    param :scope, type: "string", desc: "Filter by a predefined scope. Available scopes: 'paid', 'pending', 'verified', 'unverified'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      return { error: "At least one filter (fund_ids, folio_ids, scope, or query) or aggregate must be provided for list_capital_remittances as the dataset is too large." }.to_json if fund_ids.blank? && folio_ids.blank? && scope.blank? && (query.blank? || query.values.all?(&:blank?)) && aggregate.blank?

      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @assistant.list_capital_remittances(fund_ids: fund_ids, folio_ids: folio_ids, scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list capital distributions.
  class ListCapitalDistributions < RubyLLM::Tool
    description "List capital distributions, with optional Ransack filtering, ordering, and limiting. " \
                "fund_ids is optional. " \
                "Attributes: title, distribution_date, approved, completed, distribution_on, gross_amount, income, reinvestment. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'latest' or 'largest' requests. Example: sort: 'distribution_date desc', limit: 5."
    param :fund_ids, type: "array", desc: "List of fund IDs", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'distribution_date desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_ids: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @assistant.list_capital_distributions(fund_ids: fund_ids, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list payments made for capital remittances.
  class ListCapitalRemittancePayments < RubyLLM::Tool
    description "List capital remittance payments. Can be filtered by fund_ids, folio_ids, or a Ransack query. fund_ids and folio_ids are optional. fund_ids is not required if folio_ids is provided. At least one filter must be used. " \
                "Attributes for query: payment_date, reference_no, amount, folio_amount, tracking_amount. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'payment_date desc', limit: 10."
    param :fund_ids, type: "array", desc: "Filter by fund IDs", required: false
    param :folio_ids, type: "array", desc: "Filter by folio IDs", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_ids: nil, folio_ids: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @assistant.list_capital_remittance_payments(fund_ids: fund_ids, folio_ids: folio_ids, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list payments received from capital distributions.
  class ListCapitalDistributionPayments < RubyLLM::Tool
    description "List capital distribution payments. Can be filtered by fund_ids, folio_ids, or scope. fund_ids and folio_ids are optional. fund_ids is not required if folio_ids is provided. At least one filter must be used. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'payment_date desc', limit: 10."
    param :fund_ids, type: "array", desc: "Filter by fund IDs", required: false
    param :folio_ids, type: "array", desc: "Filter by folio IDs", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'completed', 'incomplete', 'notification_sent', 'notification_not_sent'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_ids: nil, folio_ids: nil, scope: nil, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      return { error: "At least one filter (fund_ids, folio_ids, or scope) or aggregate must be provided for list_capital_distribution_payments as the dataset is too large." }.to_json if fund_ids.blank? && folio_ids.blank? && scope.blank? && aggregate.blank?

      # We pass aggregate_field and group_by inside query for the data manager
      query = { aggregate_field: aggregate_field, group_by: group_by_field }.compact

      @assistant.list_capital_distribution_payments(fund_ids: fund_ids, folio_ids: folio_ids, scope: scope, sort: sort, limit: limit, aggregate: aggregate, query: query).to_json
    end
  end

  # Tool to list portfolio investments.
  class ListPortfolioInvestments < RubyLLM::Tool
    description "List portfolio investments, with optional Ransack filtering, ordering, and limiting. " \
                "fund_ids is optional. " \
                "Attributes: portfolio_company_name, investment_instrument_name, status, investment_date, amount, fmv, gain, cost_of_sold, quantity, sold_quantity, net_quantity, folio_id, notes, sector. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'largest' or 'most recent' investments. Example: sort: 'amount_cents desc', limit: 5."
    param :fund_ids, type: "array", desc: "List of fund IDs", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'buys', 'sells', 'conversions', 'distributed', 'not_distributed', 'proforma', 'non_proforma'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Company A', status_eq: 'Active' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'investment_date desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @assistant.list_portfolio_investments(fund_ids: fund_ids, scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list fund ratios (performance metrics).
  class ListFundRatios < RubyLLM::Tool
    description "List fund ratios, with optional Ransack filtering, ordering, and limiting. " \
                "fund_ids is optional. " \
                "Attributes: name, value, owner_type, owner_id, end_date, latest. " \
                "You can also filter by fund_ids. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'end_date desc', limit: 10."
    param :fund_ids, type: "array", desc: "Filter by fund IDs", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_eq: 'TVPI', latest_eq: true }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'end_date desc'. (Maps to Ransack `s`)", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_ids: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @assistant.list_fund_ratios(fund_ids: fund_ids, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list account entries.
  class ListAccountEntries < RubyLLM::Tool
    description "List account entries (ALWAYS aggregated). This tool ONLY returns aggregated data (sum, count, group_by). Individual records are never returned. Aggregation is mandatory. " \
                "Attributes for filtering/grouping: name, entry_type, reporting_date, period, folio_id, amount, cumulative, generated, rule_for. " \
                "Ordering: Use `sort` for grouped results. Example: aggregate: 'group_by', group_by_field: 'entry_type', aggregate_field: 'amount', sort: 'total_cents desc'."
    param :fund_ids, type: "array", desc: "Filter by fund IDs", required: false
    param :folio_ids, type: "array", desc: "Filter by folio IDs", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'cumulative', 'not_cumulative', 'generated', 'fund_entries', 'reporting', 'accounting', 'for_folios', 'for_portfolio_investments', 'for_portfolio_companies'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on. Defaults to 'amount'.", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string for results.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'. Defaults to 'sum'.", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      raise "Aggregation is MANDATORY for list_account_entries. Provide `aggregate` ('sum', 'count', or 'group_by') and appropriate `aggregate_field`." if aggregate.blank?

      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @assistant.list_account_entries(fund_ids: fund_ids, folio_ids: folio_ids, scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # PlotChart is inherited from BaseAssistantTools
end
