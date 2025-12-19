require 'erb'

# FundAssistantTools
#
# A namespace for all the tool definitions used by the FundAssistant.
#
class FundAssistantTools < BaseAssistantTools
  # Tool to list funds with various filters.
  class ListFunds < RubyLLM::Tool
    description "Return list all funds with the committed, collected and distribution amounts, with optional Ransack filtering and ordering. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: name, currency, tracking_currency, category, tag_list, unit_types, first_close_date, last_close_date, start_date. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'name asc' or query: { s: 'first_close_date desc' }."
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'feeder_funds', 'master_funds'", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Venture', currency_eq: 'USD' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'name_asc', 'first_close_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(scope: nil, query: {}, sort: nil)
      @assistant.list_funds(scope: scope, query: query || {}, sort: sort).to_json
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
    description "List capital calls, with optional Ransack filtering and ordering. " \
                "Attributes: name, due_date, approved, call_date, status, verified, call_amount, collected_amount, percentage_called. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'due_date desc' or query: { s: 'call_date asc' }."
    param :fund_id, type: "integer", desc: "The ID of the fund", required: true
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'due_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id:, query: {}, sort: nil)
      @assistant.list_capital_calls(fund_id: fund_id, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list capital commitments.
  class ListCapitalCommitments < RubyLLM::Tool
    description "List capital commitments. Can be filtered by fund_id, folio_id, or a Ransack query. fund_id is not required if folio_id is provided. At least one filter must be used. " \
                "Attributes for query: folio_id, commitment_date, fund_close, investor_name, onboarding_completed, unit_type, committed_amount, collected_amount, call_amount, distribution_amount. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'commitment_date desc'."
    param :fund_id, type: "integer", desc: "Filter by fund ID", required: false
    param :folio_id, type: "string", desc: "Filter by a specific folio ID", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'lp_onboarding_complete', 'lp_onboarding_incomplete'", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'commitment_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id: nil, folio_id: nil, scope: nil, query: {}, sort: nil)
      raise "Either fund_id, folio_id, scope, or query must be provided." if fund_id.nil? && folio_id.nil? && scope.nil? && (query || {}).empty?

      @assistant.list_capital_commitments(fund_id: fund_id, folio_id: folio_id, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list capital remittances.
  class ListCapitalRemittances < RubyLLM::Tool
    description "List capital remittances. Can be filtered by fund_id, folio_id, scope, or a Ransack query. fund_id is not required if folio_id is provided. At least one filter must be used. " \
                "Attributes for query: folio_id, investor_name, payment_date, remittance_date, call_amount, collected_amount." \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'payment_date desc'."
    param :fund_id, type: "integer", desc: "Filter by fund ID", required: false
    param :folio_id, type: "string", desc: "Filter by a specific folio ID", required: false
    param :scope, type: "string", desc: "Filter by a predefined scope. Available scopes: 'paid', 'pending', 'verified', 'unverified'", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id: nil, folio_id: nil, scope: nil, query: {}, sort: nil)
      raise "Either fund_id, folio_id, scope, or query must be provided." if fund_id.nil? && folio_id.nil? && scope.nil? && (query || {}).empty?

      @assistant.list_capital_remittances(fund_id: fund_id, folio_id: folio_id, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list capital distributions.
  class ListCapitalDistributions < RubyLLM::Tool
    description "List capital distributions, with optional Ransack filtering and ordering. " \
                "Attributes: title, distribution_date, approved, completed, distribution_on, gross_amount, income, reinvestment. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'distribution_date desc'."
    param :fund_id, type: "integer", desc: "The ID of the fund", required: true
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'distribution_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id:, query: {}, sort: nil)
      @assistant.list_capital_distributions(fund_id: fund_id, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list payments made for capital remittances.
  class ListCapitalRemittancePayments < RubyLLM::Tool
    description "List capital remittance payments. Can be filtered by fund_id, folio_id, or a Ransack query. fund_id is not required if folio_id is provided. At least one filter must be used. " \
                "Attributes for query: payment_date, reference_no, amount, folio_amount, tracking_amount. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'payment_date desc'."
    param :fund_id, type: "integer", desc: "Filter by fund ID", required: false
    param :folio_id, type: "string", desc: "Filter by a specific folio ID", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id: nil, folio_id: nil, query: {}, sort: nil)
      raise "Either fund_id, folio_id, or query must be provided." if fund_id.nil? && folio_id.nil? && (query || {}).empty?

      @assistant.list_capital_remittance_payments(fund_id: fund_id, folio_id: folio_id, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list payments received from capital distributions.
  class ListCapitalDistributionPayments < RubyLLM::Tool
    description "List capital distribution payments. Can be filtered by fund_id, folio_id, or scope. fund_id is not required if folio_id is provided. At least one filter must be used. " \
                "Ordering: pass `sort`, e.g. sort: 'payment_date desc'."
    param :fund_id, type: "integer", desc: "Filter by fund ID", required: false
    param :folio_id, type: "string", desc: "Filter by a specific folio ID", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'completed', 'incomplete', 'notification_sent', 'notification_not_sent'", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id: nil, folio_id: nil, scope: nil, sort: nil)
      raise "Either fund_id, folio_id, or scope must be provided." if fund_id.nil? && folio_id.nil? && scope.nil?

      @assistant.list_capital_distribution_payments(fund_id: fund_id, folio_id: folio_id, scope: scope, sort: sort).to_json
    end
  end

  # Tool to list portfolio investments.
  class ListPortfolioInvestments < RubyLLM::Tool
    description "List portfolio investments, with optional Ransack filtering and ordering. " \
                "Attributes: portfolio_company_name, investment_instrument_name, status, investment_date, amount, fmv, gain, cost_of_sold, quantity, sold_quantity, net_quantity, folio_id, notes, sector. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'investment_date desc'."
    param :fund_id, type: "integer", desc: "The ID of the fund", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'buys', 'sells', 'conversions', 'distributed', 'not_distributed', 'proforma', 'non_proforma'", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Company A', status_eq: 'Active' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'investment_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id: nil, scope: nil, query: {}, sort: nil)
      @assistant.list_portfolio_investments(fund_id: fund_id, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list fund ratios (performance metrics).
  class ListFundRatios < RubyLLM::Tool
    description "List fund ratios, with optional Ransack filtering and ordering. " \
                "Attributes: name, value, owner_type, owner_id, end_date, latest. " \
                "You can also filter by fund_id. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'end_date desc'."
    param :fund_id, type: "integer", desc: "Filter by fund ID", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_eq: 'TVPI', latest_eq: true }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'end_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id: nil, query: {}, sort: nil)
      @assistant.list_fund_ratios(fund_id: fund_id, query: query || {}, sort: sort).to_json
    end
  end

  # PlotChart is inherited from BaseAssistantTools
end
