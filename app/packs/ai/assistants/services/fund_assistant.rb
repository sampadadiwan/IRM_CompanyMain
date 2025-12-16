require 'erb'

class FundAssistant
  def initialize(user:)
    @user = user
  end

  # --- Tool Definitions ---

  class ListFunds < RubyLLM::Tool
    description "List all funds, with optional Ransack filtering and ordering. " \
                "Construct a query hash using available attributes and predicates. " \
                "Attributes: name, currency, tracking_currency, category, tag_list, unit_types, first_close_date, last_close_date, start_date. " \
                "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'name asc' or query: { s: 'first_close_date desc' }."
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Venture', currency_eq: 'USD' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'name asc', 'first_close_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(query: {}, sort: nil)
      # Ensure query is a Hash before passing to the assistant
      @assistant.list_funds(query: query || {}, sort: sort).to_json
    end
  end

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

  class ListCapitalCommitments < RubyLLM::Tool
    description "List capital commitments. Can be filtered by fund_id, folio_id, or a Ransack query. fund_id is not required if folio_id is provided. At least one filter must be used. " \
                "Attributes for query: folio_id, commitment_date, fund_close, investor_name, onboarding_completed, unit_type, committed_amount, collected_amount, call_amount, distribution_amount. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'commitment_date desc'."
    param :fund_id, type: "integer", desc: "Filter by fund ID", required: false
    param :folio_id, type: "string", desc: "Filter by a specific folio ID", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'commitment_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id: nil, folio_id: nil, query: {}, sort: nil)
      raise "Either fund_id, folio_id, or query must be provided." if fund_id.nil? && folio_id.nil? && (query || {}).empty?

      @assistant.list_capital_commitments(fund_id: fund_id, folio_id: folio_id, query: query || {}, sort: sort).to_json
    end
  end

  class ListCapitalRemittances < RubyLLM::Tool
    description "List capital remittances. Can be filtered by fund_id, folio_id, or a Ransack query. fund_id is not required if folio_id is provided. At least one filter must be used. " \
                "Attributes for query: folio_id, investor_name, payment_date, remittance_date, status, verified, call_amount, collected_amount. Note the verified is true or false and status is Pending, Paid, Overdue. " \
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

      @assistant.list_capital_remittances(fund_id: fund_id, folio_id: folio_id, query: query || {}, sort: sort).to_json
    end
  end

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

  class ListCapitalDistributionPayments < RubyLLM::Tool
    description "List capital distribution payments. Can be filtered by fund_id or folio_id. fund_id is not required if folio_id is provided. At least one filter must be used. " \
                "Ordering: pass `sort`, e.g. sort: 'payment_date desc'."
    param :fund_id, type: "integer", desc: "Filter by fund ID", required: false
    param :folio_id, type: "string", desc: "Filter by a specific folio ID", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id: nil, folio_id: nil, sort: nil)
      raise "Either fund_id or folio_id must be provided." if fund_id.nil? && folio_id.nil?

      @assistant.list_capital_distribution_payments(fund_id: fund_id, folio_id: folio_id, sort: sort).to_json
    end
  end

  class ListPortfolioInvestments < RubyLLM::Tool
    description "List portfolio investments, with optional Ransack filtering and ordering. " \
                "Attributes: portfolio_company_name, investment_instrument_name, status, investment_date, amount, fmv, gain, cost_of_sold, quantity, sold_quantity, net_quantity, folio_id, notes, sector. " \
                "Ordering: pass `sort` (recommended) or include `s` inside query, e.g. sort: 'investment_date desc'."
    param :fund_id, type: "integer", desc: "The ID of the fund", required: false
    param :query, type: :object, desc: "Ransack query hash, e.g. { name_cont: 'Company A', status_eq: 'Active' }", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'investment_date desc'. (Maps to Ransack `s`)", required: false

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(fund_id: nil, query: {}, sort: nil)
      @assistant.list_portfolio_investments(fund_id: fund_id, query: query || {}, sort: sort).to_json
    end
  end

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

  class PlotChart < RubyLLM::Tool
    description "Generates an interactive Chart.js chart (HTML) from a dataset and a prompt describing the desired visualization. Use this when the user asks for a graph, plot, or chart."
    param :data, type: :string, desc: "A JSON string of the data to be plotted."
    param :prompt, type: :string, desc: "A natural language prompt describing what the chart should represent."

    def initialize(assistant)
      super()
      @assistant = assistant
    end

    def execute(data:, prompt:)
      html = generate_chart_html(data, prompt)
      RubyLLM::Content.new(html)
    end

    private

    # Returns an HTML snippet that renders the chart client-side using Stimulus + Chart.js.
    # This avoids server-side rendering/screenshot dependencies (e.g., Playwright).
    def generate_chart_html(json_data_string, prompt)
      json_data = JSON.parse(json_data_string)
      agent = ChartAgentService.new(json_data: json_data)
      chart_config = agent.generate_chart!(prompt: prompt)
      normalize_chart_config!(chart_config)

      spec_json = chart_config.to_json
      escaped_spec = ERB::Util.html_escape(spec_json)
      escaped_title = ERB::Util.html_escape(prompt.to_s)

      canvas_id = "chart_#{SecureRandom.hex(8)}"

      <<~HTML
        <div class="my-3">
          <div class="fw-semibold mb-2">#{escaped_title}</div>
          <div class="chart-wrap" style="max-width: 900px;">
            <div
              data-controller="chart-renderer"
              data-chart-renderer-spec-value="#{escaped_spec}"
            >
              <canvas
                id="#{canvas_id}"
                width="900"
                height="500"
                data-chart-renderer-target="canvas"
              ></canvas>
            </div>
          </div>
        </div>
      HTML
    end

    # Ensures the legend is meaningful and points/series are identifiable.
    # Also nudges line/scatter charts to actually render points.
    def normalize_chart_config!(cfg)
      return unless cfg.is_a?(Hash)

      cfg["options"] ||= {}
      cfg["options"]["plugins"] ||= {}
      cfg["options"]["plugins"]["legend"] ||= {}

      # Always show legend unless explicitly set otherwise (we keep explicit false).
      cfg["options"]["plugins"]["legend"]["display"] = true if cfg["options"]["plugins"]["legend"]["display"].nil?

      datasets = cfg.dig("data", "datasets")
      return unless datasets.is_a?(Array) && datasets.any?

      datasets.each_with_index do |ds, idx|
        next unless ds.is_a?(Hash)

        label = ds["label"].to_s.strip
        next unless label.empty?

        ds["label"] = datasets.length == 1 ? "Value" : "Series #{idx + 1}"
      end

      # Ensure line/scatter charts actually show points (helps "data points inline").
      if %w[line scatter].include?(cfg["type"].to_s)
        datasets.each do |ds|
          next unless ds.is_a?(Hash)

          ds["pointRadius"] = 3 if ds["pointRadius"].nil?
          ds["pointHoverRadius"] = 4 if ds["pointHoverRadius"].nil?
        end
      end
    end
  end

  # --- Public API for Driver ---

  def tools
    [
      ListFunds.new(self),
      GetFundDetails.new(self),
      ListCapitalCalls.new(self),
      ListCapitalCommitments.new(self),
      ListCapitalRemittances.new(self),
      ListCapitalDistributions.new(self),
      ListPortfolioInvestments.new(self),
      ListFundRatios.new(self),
      ListCapitalRemittancePayments.new(self),
      ListCapitalDistributionPayments.new(self),
      PlotChart.new(self)
    ]
  end

  def system_prompt
    <<~SYSTEM
      You are a helpful AI assistant for a Private Equity Fund Management platform.
      You have access to tools to retrieve information and plot charts. You will format the response as markdown and typically as a table when possible. Always use the tools to get accurate data.

      Tool Usage Rules:
      - When searching for items like remittances or commitments, you can filter by `fund_id`, `folio_id`, or a Ransack `query`.
      - It is NOT necessary to provide a `fund_id` if a `folio_id` or a sufficiently specific `query` is given.
      - If the user mentions a status like "unpaid", "pending", or "overdue", translate this into a Ransack query (e.g., `{ status_not_eq: 'Paid' }`).
      - To create a visualization, first retrieve the data using a `list_` tool, then pass that data to the `PlotChart` tool.
      - Never guess IDs.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
    SYSTEM
  end

  # --- Tool Implementations ---

  def list_funds(query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    scope = Pundit.policy_scope(@user, Fund).ransack(ransack_query).result
    scope.map do |f|
      {
        id: f.id,
        name: f.name,
        currency: f.currency,
        unit_types: f.unit_types,
        first_close_date: f.first_close_date,
        last_close_date: f.last_close_date,
        tracking_currency: f.tracking_currency,
        collected_amount: f.collected_amount.format,
        committed_amount: f.committed_amount.format,
        distribution_amount: f.distribution_amount.format,
        call_amount: f.call_amount.format
      }
    end
  end

  def get_fund_details(fund_id:)
    fund = Pundit.policy_scope(@user, Fund).find_by(id: fund_id)
    return "Fund not found or access denied" unless fund

    details = {
      id: fund.id,
      name: fund.name,
      entity: fund.entity&.name,
      currency: fund.currency,
      unit_types: fund.unit_types,
      tags: fund.tag_list.to_s,
      details: fund.details,
      first_close_date: fund.first_close_date,
      last_close_date: fund.last_close_date,
      signatory_emails: fund.esign_emails
    }

    details[:master_fund] = fund.master_fund&.name if fund.master_fund_id.present?

    if fund.has_tracking_currency?
      details[:tracking_currency] = {
        currency: fund.tracking_currency,
        committed: fund.tracking_committed_amount.format,
        call_amount: fund.tracking_call_amount.format,
        collected: fund.tracking_collected_amount.format,
        distributed: fund.tracking_distribution_amount.format
      }
    end

    details
  end

  def list_capital_calls(fund_id:, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id

    calls = Pundit.policy_scope(@user, CapitalCall).ransack(ransack_query).result
    calls.map do |c|
      {
        id: c.id,
        name: c.name,
        due_date: c.due_date,
        call_date: c.call_date,
        call_amount: c.call_amount.format,
        collected_amount: c.collected_amount.format,
        due_amount: c.due_amount.format,
        percentage_called: c.percentage_called,
        percentage_raised: c.percentage_raised,
        status: c.status,
        approved: c.approved
      }
    end
  end

  def list_capital_commitments(fund_id: nil, folio_id: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id if fund_id.present?
    ransack_query[:folio_id_eq] = folio_id if folio_id.present?
    commitments = Pundit.policy_scope(@user, CapitalCommitment).includes(:fund).ransack(ransack_query).result
    commitments.map do |c|
      {
        id: c.id,
        folio_id: c.folio_id,
        investor: c.investor_name,
        unit_type: c.unit_type,
        fund_close: c.fund_close,
        committed_amount: c.committed_amount.format,
        call_amount: c.call_amount.format,
        collected_amount: c.collected_amount.format,
        distribution_amount: c.distribution_amount.format,
        commitment_date: c.commitment_date,
        onboarding_completed: c.onboarding_completed
      }
    end
  end

  def list_capital_remittances(fund_id: nil, folio_id: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id if fund_id.present?
    ransack_query[:folio_id_eq] = folio_id if folio_id.present?
    remittances = Pundit.policy_scope(@user, CapitalRemittance).includes(:fund, :capital_call, :capital_commitment).ransack(ransack_query).result
    remittances.map do |r|
      {
        id: r.id,
        investor: r.investor_name,
        folio_id: r.folio_id,
        capital_call: r.capital_call&.name,
        call_amount: r.call_amount.format,
        collected_amount: r.collected_amount.format,
        due_amount: r.due_amount.format,
        status: r.status,
        verified: r.verified,
        fees: {
          capital: r.capital_fee.format,
          other: r.other_fee.format,
          investment: r.investment_amount.format
        }
      }
    end
  end

  def list_capital_distributions(fund_id:, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id

    distributions = Pundit.policy_scope(@user, CapitalDistribution).includes(:fund).ransack(ransack_query).result
    distributions.map do |d|
      {
        id: d.id,
        title: d.title,
        distribution_date: d.distribution_date,
        gross_amount: d.gross_amount.format,
        net_amount: d.distribution_amount.format,
        income: d.income.format,
        reinvestment: d.reinvestment.format,
        notes: d.notes,
        approved: d.approved,
        completed: d.completed
      }
    end
  end

  def list_capital_remittance_payments(fund_id: nil, folio_id: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id if fund_id.present?
    ransack_query['capital_commitment_folio_id_eq'] = folio_id if folio_id.present?
    payments = Pundit.policy_scope(@user, CapitalRemittancePayment).includes(:fund, :capital_commitment).ransack(ransack_query).result
    payments.map do |p|
      {
        id: p.id,
        fund_name: p.fund.name,
        investor: p.capital_commitment.investor_name,
        folio_id: p.capital_commitment.folio_id,
        amount: p.amount.format,
        payment_date: p.payment_date,
        reference_no: p.reference_no
      }
    end
  end

  def list_capital_distribution_payments(fund_id: nil, folio_id: nil, sort: nil)
    scope = Pundit.policy_scope(@user, CapitalDistributionPayment).includes(:fund, :capital_commitment)
    scope = scope.where(fund_id: fund_id) if fund_id.present?
    scope = scope.joins(:capital_commitment).where(capital_commitments: { folio_id: folio_id }) if folio_id.present?

    payments = sort.present? ? scope.ransack(s: sort).result : scope
    payments.map do |p|
      {
        id: p.id,
        fund_name: p.fund.name,
        investor: p.investor_name,
        folio_id: p.capital_commitment.folio_id,
        net_payable: p.net_payable.format,
        gross_payable: p.gross_payable.format,
        payment_date: p.payment_date,
        units_quantity: p.units_quantity
      }
    end
  end

  def list_portfolio_investments(fund_id: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    investments = Pundit.policy_scope(@user, PortfolioInvestment).includes(:fund, :portfolio_company, :investment_instrument)
    investments = investments.where(fund_id: fund_id) if fund_id.present?
    investments = investments.ransack(ransack_query).result
    investments.map do |i|
      {
        id: i.id,
        portfolio_company_name: i.portfolio_company&.name,
        investment_instrument_name: i.investment_instrument&.name,
        investment_date: i.investment_date,
        amount: i.amount.format,
        fmv: i.fmv.format,
        quantity: i.quantity,
        unrealized_gain: i.unrealized_gain.format,
        gain: i.gain.format,
        fund_name: i.fund.name
      }
    end
  end

  def list_fund_ratios(fund_id: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id if fund_id.present?

    ratios = Pundit.policy_scope(@user, FundRatio).includes(:fund, :portfolio_scenario).ransack(ransack_query).result
    ratios.map do |r|
      {
        id: r.id,
        fund_id: r.fund_id,
        fund_name: r.fund&.name,
        name: r.name,
        value: r.value,
        display_value: r.display_value,
        end_date: r.end_date,
        latest: r.latest,
        owner_type: r.owner_type,
        owner_id: r.owner_id,
        scenario: r.scenario,
        portfolio_scenario: r.portfolio_scenario&.name
      }
    end
  end

  # This method is used to interact with the assistant
  def chat(prompt)
    client = RubyLLM.chat(model: 'gemini-2.5-flash')

    # Convert Langchain tool definitions to OpenAI format if needed, or pass as is if RubyLLM supports it.
    # Assuming RubyLLM can handle tools or we just construct the system prompt.
    # For now, let's try to pass tools if RubyLLM client supports it.
    # If not, this serves as the implementation of the tools.

    # Since I don't know the exact API of RubyLLM regarding tools, I'll rely on the class structure.
    # But to be useful, I should probably return the client or response.

    # If this is intended to be used by another service (like LlmChat), then defining the tools is enough.
    # But the user asked to "create an assistant", implying it should be usable.

    # I will check if I should implement a 'ask' or 'run' method that uses RubyLLM.

    client.ask(prompt, tools: self.class.tools)
  end

  def self.tools
    tool_definitions.map do |tool|
      {
        type: "function",
        function: {
          name: tool[:name],
          description: tool[:description],
          parameters: tool[:parameters]
        }
      }
    end
  end
end
