# frozen_string_literal: true

class CashFlowStressScenarioTool
  extend Langchain::ToolDefinition

  # rubocop:disable Metrics/BlockLength
  define_function :simulate_scenario,
                  description: "Simulates a what-if cash flow scenario by applying adjustments " \
                               "to the latest agent run results. Use this whenever the analyst " \
                               "asks 'what if', 'what happens if', 'suppose we deploy', or any " \
                               "hypothetical question about investments, expenses, or capital " \
                               "calls. Do NOT use for questions about actual/current data; " \
                               "answer those from the provided context." do
    property :fund_name,
             type: "string",
             description: "Name of the fund to simulate. Omit if agent has only one fund.",
             required: false

    property :extra_investment_cents,
             type: "integer",
             description: "Additional unplanned investment in cents not yet in the system. " \
                          "E.g. 50Cr = 5000000000. For 'what if we deploy more' questions.",
             required: false

    property :delay_investment_name,
             type: "string",
             description: "Partial or full name of an existing planned investment to delay. " \
                          "Use together with delay_days.",
             required: false

    property :delay_days,
             type: "integer",
             description: "Number of days to delay the investment in delay_investment_name. " \
                          "If this pushes it beyond 90 days it exits the current window.",
             required: false

    property :remove_investment_name,
             type: "string",
             description: "Partial or full name of a planned investment to cancel entirely. " \
                          "For 'what if deal falls through' questions.",
             required: false

    property :capital_call_inflow_cents,
             type: "integer",
             description: "Cash inflow in cents from calling capital from investors. " \
                          "E.g. calling 100Cr = 10000000000.",
             required: false

    property :expense_multiplier,
             type: "number",
             description: "Multiply estimated expenses by this factor. " \
                          "1.2 = 20% increase, 0.8 = 20% decrease. Default 1.0.",
             required: false

    property :extra_expense_cents,
             type: "integer",
             description: "Additional one-off flat expense in cents on top of current estimate.",
             required: false
  end
  # rubocop:enable Metrics/BlockLength

  def initialize(support_agent:)
    @support_agent = support_agent
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def simulate_scenario(
    fund_name: nil,
    extra_investment_cents: 0,
    delay_investment_name: nil,
    delay_days: 0,
    remove_investment_name: nil,
    capital_call_inflow_cents: 0,
    expense_multiplier: 1.0,
    extra_expense_cents: 0
  )
    fund = find_fund(fund_name)
    return "Fund not found. Available funds: #{available_fund_names.join(', ')}" unless fund

    report = SupportAgentReport
             .where(support_agent: @support_agent, owner: fund, status: :completed)
             .order(updated_at: :desc)
             .first
    return "No completed cash flow run found for #{fund.name}. Please run the agent first." unless report

    baseline = report.json_fields
    currency = baseline["currency"] || fund.currency

    # --- Apply adjustments ---

    adj_cash = baseline["cash_available"].to_i + capital_call_inflow_cents.to_i

    inv_list = (baseline["investment_list"] || []).map(&:dup)

    if delay_investment_name.present? && delay_days.to_i.positive?
      inv = inv_list.find { |i| i["name"].to_s.downcase.include?(delay_investment_name.downcase) }
      if inv
        original_date = begin
          Date.parse(inv["expected_date"].to_s)
        rescue StandardError
          Date.current
        end
        inv["expected_date"] = (original_date + delay_days.to_i.days).to_s
        inv["_delayed"] = true
      end
    end

    inv_list.reject! { |i| i["name"].to_s.downcase.include?(remove_investment_name.downcase) } if remove_investment_name.present?

    window_end = Date.current + 90.days
    active_investments = inv_list.select do |i|
      date = begin
        Date.parse(i["expected_date"].to_s)
      rescue StandardError
        nil
      end
      date.nil? || date <= window_end
    end

    adj_investments  = active_investments.sum { |i| i["amount_cents"].to_i } + extra_investment_cents.to_i
    adj_expenses     = ((baseline["estimated_expenses"].to_i * (expense_multiplier || 1.0)) + extra_expense_cents.to_i).round
    buffer           = baseline["buffer_required"].to_i

    # --- Recompute ---

    adj_net    = adj_cash - adj_investments - adj_expenses - buffer
    outflow    = (adj_investments + adj_expenses).to_f / 90
    adj_runway = outflow.positive? ? (adj_cash / outflow).round : 999

    adj_status = if adj_net.negative? then "SHORTFALL"
                 elsif adj_runway < 90 then "WATCH"
                 else "SURPLUS"
                 end

    adj_call = adj_net.negative? ? (adj_net.abs + buffer) : 0

    format_result(
      fund: fund, currency: currency, baseline: baseline,
      adj_cash: adj_cash, adj_investments: adj_investments,
      adj_expenses: adj_expenses, buffer: buffer,
      adj_net: adj_net, adj_runway: adj_runway,
      adj_status: adj_status, adj_call: adj_call,
      active_investments: active_investments,
      extra_investment_cents: extra_investment_cents,
      capital_call_inflow_cents: capital_call_inflow_cents,
      delay_investment_name: delay_investment_name, delay_days: delay_days,
      remove_investment_name: remove_investment_name,
      expense_multiplier: expense_multiplier, extra_expense_cents: extra_expense_cents
    )
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  private

  def find_fund(name)
    fund_ids = (@support_agent.json_fields["funds"] || []).pluck("fund_id")
    return Fund.find_by(id: fund_ids.first) if name.blank?

    Fund.where(id: fund_ids).find { |f| f.name.downcase.include?(name.downcase) }
  end

  def available_fund_names
    fund_ids = (@support_agent.json_fields["funds"] || []).pluck("fund_id")
    Fund.where(id: fund_ids).pluck(:name)
  end

  def fmt(cents, currency)
    Money.new(cents.to_i, currency).format
  end

  def delta(diff, currency)
    return "—" if diff.zero?

    sign = diff.positive? ? "+" : ""
    "#{sign}#{fmt(diff, currency)}"
  end

  def format_result(fund:, currency:, baseline:, adj_cash:, adj_investments:,
                    adj_expenses:, buffer:, adj_net:, adj_runway:, adj_status:,
                    adj_call:, active_investments:, **adjustments)
    base_cash        = baseline["cash_available"].to_i
    base_investments = baseline["upcoming_investments"].to_i
    base_expenses    = baseline["estimated_expenses"].to_i
    base_net         = baseline["net_position"].to_i
    base_runway      = baseline["runway_days"].to_i
    base_status      = (baseline["fund_status"] || baseline["status"] || "unknown").upcase
    base_call        = baseline["recommended_call"].to_i

    lines = []
    lines << "STRESS SCENARIO RESULT: #{fund.name}"
    lines << ""
    lines << "Adjustments Applied:"
    lines << "  Capital call inflow: #{fmt(adjustments[:capital_call_inflow_cents], currency)}" if adjustments[:capital_call_inflow_cents].to_i.positive?
    lines << "  Extra investment: #{fmt(adjustments[:extra_investment_cents], currency)}" if adjustments[:extra_investment_cents].to_i.positive?
    lines << "  Delay '#{adjustments[:delay_investment_name]}' by #{adjustments[:delay_days]} days" if adjustments[:delay_investment_name].present?
    lines << "  Remove '#{adjustments[:remove_investment_name]}'" if adjustments[:remove_investment_name].present?
    multiplier = adjustments[:expense_multiplier].to_f
    lines << "  Expense multiplier: #{multiplier}x" if (multiplier - 1.0).abs > Float::EPSILON
    lines << "  Extra expense: #{fmt(adjustments[:extra_expense_cents], currency)}" if adjustments[:extra_expense_cents].to_i.positive?
    lines << ""
    lines << "Comparison (Baseline vs Scenario):"
    lines << "  Cash Available: #{fmt(base_cash, currency)} → #{fmt(adj_cash, currency)} (#{delta(adj_cash - base_cash, currency)})"
    lines << "  Upcoming Investments: #{fmt(base_investments, currency)} → #{fmt(adj_investments, currency)} (#{delta(adj_investments - base_investments, currency)})"
    lines << "  Expenses (90d): #{fmt(base_expenses, currency)} → #{fmt(adj_expenses, currency)} (#{delta(adj_expenses - base_expenses, currency)})"
    lines << "  Buffer Required: #{fmt(buffer, currency)} → #{fmt(buffer, currency)} (no change)"
    lines << "  Net Position: #{fmt(base_net, currency)} → #{fmt(adj_net, currency)} (#{delta(adj_net - base_net, currency)})"
    lines << "  Runway: #{base_runway} days → #{adj_runway} days (#{'+' if adj_runway >= base_runway}#{adj_runway - base_runway} days)"
    lines << "  Status: #{base_status} → #{adj_status}"
    lines << "  Recommended Call: #{fmt(base_call, currency)} → #{fmt(adj_call, currency)} (#{delta(adj_call - base_call, currency)})"
    lines << ""

    if active_investments.any?
      lines << "Investments Active in Scenario (within 90-day window):"
      active_investments.each do |inv|
        tag = inv["_delayed"] ? " [DELAYED]" : ""
        lines << "  #{inv['name']}#{tag}: #{fmt(inv['amount_cents'], currency)} (expected: #{inv['expected_date']})"
      end
      lines << ""
    end

    lines << "Note: Scenario uses stored baseline. Re-run the agent for updated actuals."
    lines.join("\n")
  end
end
