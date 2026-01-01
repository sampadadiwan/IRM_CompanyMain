# SpecificFundAssistantTools
#
# A namespace for specialized tool definitions for SpecificFundAssistant.
# These tools remove the `fund_id` parameter where possible since it's hardcoded in the data manager.
#
class SpecificFundAssistantTools < FundAssistantTools
  # Tool to retrieve detailed information about the current fund.
  class GetSpecificFundDetails < RubyLLM::Tool
    def name = "get_fund_details"
    description "Get details of the current fund"

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute
      @data_manager.get_fund_details.to_json
    end
  end

  # Tool to list capital calls for the current fund.
  class ListSpecificFundCapitalCalls < RubyLLM::Tool
    def name = "list_capital_calls"
    description "List capital calls for the current fund, with optional Ransack filtering and ordering. " \
                "Attributes: name, due_date, approved, call_date, status, verified, call_amount, collected_amount, percentage_called. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'due_date desc'."
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'due_date desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(query: {}, sort: nil)
      @data_manager.list_capital_calls(query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list capital commitments for the current fund.
  class ListSpecificFundCapitalCommitments < RubyLLM::Tool
    def name = "list_capital_commitments"
    description "List capital commitments for the current fund. " \
                "Attributes for query: folio_id, commitment_date, fund_close, investor_name, onboarding_completed, unit_type, committed_amount, collected_amount, call_amount, distribution_amount. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'commitment_date desc'."
    param :folio_id, type: :string, desc: "Filter by a specific folio ID", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'lp_onboarding_complete', 'lp_onboarding_incomplete'", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'commitment_date desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_id: nil, scope: nil, query: {}, sort: nil)
      @data_manager.list_capital_commitments(folio_id: folio_id, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list capital remittances for the current fund.
  class ListSpecificFundCapitalRemittances < RubyLLM::Tool
    def name = "list_capital_remittances"
    description "List capital remittances for the current fund. " \
                "Attributes for query: folio_id, investor_name, payment_date, remittance_date, call_amount, collected_amount." \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'payment_date desc'."
    param :folio_id, type: :string, desc: "Filter by a specific folio ID", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'paid', 'pending', 'verified', 'unverified'", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_id: nil, scope: nil, query: {}, sort: nil)
      @data_manager.list_capital_remittances(folio_id: folio_id, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list capital distributions for the current fund.
  class ListSpecificFundCapitalDistributions < RubyLLM::Tool
    def name = "list_capital_distributions"
    description "List capital distributions for the current fund, with optional Ransack filtering and ordering. " \
                "Attributes: title, distribution_date, approved, completed, distribution_on, gross_amount, income, reinvestment. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'distribution_date desc'."
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'distribution_date desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(query: {}, sort: nil)
      @data_manager.list_capital_distributions(query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list payments for capital remittances in the current fund.
  class ListSpecificFundCapitalRemittancePayments < RubyLLM::Tool
    def name = "list_capital_remittance_payments"
    description "List capital remittance payments for the current fund. " \
                "Attributes for query: payment_date, reference_no, amount, folio_amount, tracking_amount. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'payment_date desc'."
    param :folio_id, type: :string, desc: "Filter by a specific folio ID", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_id: nil, query: {}, sort: nil)
      @data_manager.list_capital_remittance_payments(folio_id: folio_id, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list payments received from capital distributions for the current fund.
  class ListSpecificFundCapitalDistributionPayments < RubyLLM::Tool
    def name = "list_capital_distribution_payments"
    description "List capital distribution payments for the current fund. " \
                "Ordering: pass `sort`, e.g. sort: 'payment_date desc'."
    param :folio_id, type: :string, desc: "Filter by a specific folio ID", required: false
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'completed', 'incomplete', 'notification_sent', 'notification_not_sent'", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(folio_id: nil, scope: nil, sort: nil)
      @data_manager.list_capital_distribution_payments(folio_id: folio_id, scope: scope, sort: sort).to_json
    end
  end

  # Tool to list portfolio investments for the current fund.
  class ListSpecificFundPortfolioInvestments < RubyLLM::Tool
    def name = "list_portfolio_investments"
    description "List portfolio investments for the current fund, with optional Ransack filtering and ordering. " \
                "Attributes: portfolio_company_name, investment_instrument_name, status, investment_date, amount, fmv, gain, cost_of_sold, quantity, sold_quantity, net_quantity, folio_id, notes, sector. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'investment_date desc'."
    param :scope, type: :string, desc: "Filter by a predefined scope. Available scopes: 'buys', 'sells', 'conversions', 'distributed', 'not_distributed', 'proforma', 'non_proforma'", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Company A', status_eq: 'Active' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'investment_date desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(scope: nil, query: {}, sort: nil)
      @data_manager.list_portfolio_investments(scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list fund ratios for the current fund.
  class ListSpecificFundRatios < RubyLLM::Tool
    def name = "list_fund_ratios"
    description "List performance metrics (ratios) for the current fund, with optional Ransack filtering and ordering. " \
                "Attributes: name, value, end_date, latest. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'end_date desc'."
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_eq: 'TVPI', latest_eq: true }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'end_date desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(query: {}, sort: nil)
      @data_manager.list_fund_ratios(query: query || {}, sort: sort).to_json
    end
  end

  # PlotChart is inherited from BaseAssistantTools
  class PlotChart < BaseAssistantTools::PlotChart
    def name = "plot_chart"
  end
end
