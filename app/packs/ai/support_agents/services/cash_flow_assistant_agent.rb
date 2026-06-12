# frozen_string_literal: true

# Analyzes cash flow across configured funds and generates reports.
#
# CashFlowAssistantAgent checks data freshness, calculates cash positions,
# and sends consolidated reports to fund managers. Funds with stale data
# are blocked (no report generated) to prevent misleading recommendations.
#
# @example Run the agent
#   CashFlowAssistantAgent.call(support_agent_id: 1, target: entity, user_id: 10)
#
# @see SupportAgentService
class CashFlowAssistantAgent < SupportAgentService
  DESCRIPTION = "Analyzes cash flow across configured funds and sends consolidated reports to fund managers."

  LONG_DESCRIPTION = <<~DESC
    Analyzes cash flow across a configured set of funds and delivers a consolidated report
    to fund managers. Targets the entity itself and iterates over the funds listed in json_fields.

    Steps:
    • Staleness Check — verifies that cash flow data for each fund is current. Funds with stale
      data are excluded from the report to prevent misleading recommendations.
    • Cash Flow Calculation — computes cash positions using configured account tags:
      cash_tags (inflows), expense_tags (outflows), buffer_tags (reserve accounts).
    • Generate Reports — produces a per-fund report with balance, estimated burn rate,
      runway, and a narrative summary.
    • Send Email — delivers the consolidated report to all addresses in report_recipients.

    Configuration: funds (list of fund IDs to include), report_recipients (comma-separated
    email addresses), cash_tags / expense_tags / buffer_tags (comma-separated account tags).
    Designed for weekly or monthly scheduled runs.
  DESC

  STEP_LABELS = {
    initialize_agent: "Initialize",
    check_data_staleness: "Staleness Check",
    calculate_cash_positions: "Cash Flow Calc",
    generate_fund_reports: "Generate Reports",
    send_report_email: "Send Email",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :check_data_staleness
  step :calculate_cash_positions
  step :generate_fund_reports
  step :send_report_email
  step :generate_progress_reports

  # The agent runs against the organization entity itself.
  # Internally it iterates over configured funds.
  def targets(entity_id)
    Entity.where(id: entity_id)
  end

  private

  # ─── Step 1: Initialize ─────────────────────────────────────

  def initialize_agent(ctx, **)
    super
    @config            = @support_agent.json_fields
    @funds_config      = @config["funds"] || []
    @report_recipients = (@config["report_recipients"] || "").split(",").map(&:strip).compact_blank
    @cash_tags         = (@config["cash_tags"] || "").split(",").map(&:strip).compact_blank
    @expense_tags      = (@config["expense_tags"] || "").split(",").map(&:strip).compact_blank
    @buffer_tags       = (@config["buffer_tags"] || "").split(",").map(&:strip).compact_blank

    ctx[:fund_results] = []
    ctx[:issues] = { staleness_issues: [], calculation_issues: [] }

    report = ctx[:support_agent_report]
    if report
      mark_step_running(report, :initialize_agent)
      mark_step_success(report, :initialize_agent,
                        message: "Loaded config for #{@funds_config.size} fund(s)")
    end
    true
  end

  # ─── Step 2: Staleness Gate ─────────────────────────────────

  def check_data_staleness(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_data_staleness) if report

    checker = CashFlowStalenessChecker.new(@support_agent)
    ctx[:fund_results] = checker.check_all_funds

    blocked = ctx[:fund_results].count { |f| f[:status] == "blocked" }
    ready   = ctx[:fund_results].count { |f| f[:status] == "ready" }

    if report
      if ready.zero? && blocked.positive?
        mark_step_failed(report, :check_data_staleness,
                         message: "All #{blocked} fund(s) blocked — stale data",
                         count: blocked)
      else
        mark_step_success(report, :check_data_staleness,
                          message: "#{ready} ready, #{blocked} blocked",
                          count: ready)
      end
    end
    true
  end

  # ─── Step 3: Cash Flow Calculation ──────────────────────────

  def calculate_cash_positions(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :calculate_cash_positions) if report

    ready_funds = ctx[:fund_results].select { |f| f[:status] == "ready" }

    if ready_funds.empty?
      if report
        mark_step_skipped(report, :calculate_cash_positions,
                          message: "No funds ready for calculation")
      end
      return true
    end

    ready_funds.each { |fund_result| calculate_for_fund(fund_result) }

    if report
      mark_step_success(report, :calculate_cash_positions,
                        message: "Calculated for #{ready_funds.size} fund(s)",
                        count: ready_funds.size)
    end
    true
  end

  # ─── Step 4: Save Per-Fund Reports ─────────────────────────

  def generate_fund_reports(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :generate_fund_reports) if report

    ctx[:fund_results].each do |fund_result|
      fund = Fund.find_by(id: fund_result[:fund_id])
      next unless fund

      fund_report = SupportAgentReport.find_or_initialize_by(
        owner: fund, support_agent: @support_agent
      )
      fund_report.json_fields = fund_result.deep_stringify_keys
      fund_report.status = fund_result[:status] == "blocked" ? :failed : :completed
      fund_report.save!

      # Save HTML report to Fund's private Reports folder
      next if fund_result[:status] == "blocked"

      begin
        CashFlowReportRenderer.new(fund_result, @support_agent)
                              .save_to_fund_folder(fund, ctx[:user_id])
      rescue StandardError => e
        Rails.logger.error { "[CashFlowAssistantAgent] Failed to save report doc for #{fund.name}: #{e.message}" }
      end
    end

    if report
      mark_step_success(report, :generate_fund_reports,
                        message: "Saved #{ctx[:fund_results].size} fund report(s)",
                        count: ctx[:fund_results].size)
    end
    true
  end

  # ─── Step 5: Send Email ─────────────────────────────────────

  def send_report_email(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :send_report_email) if report

    if @report_recipients.empty?
      if report
        mark_step_skipped(report, :send_report_email,
                          message: "No report recipients configured")
      end
      return true
    end

    CashFlowReportMailer.with(
      support_agent_id: @support_agent.id,
      fund_results: ctx[:fund_results],
      recipients: @report_recipients,
      currency: @funds_config.first&.dig("currency") || "INR"
    ).send_report.deliver_later

    if report
      mark_step_success(report, :send_report_email,
                        message: "Queued for #{@report_recipients.size} recipient(s)",
                        count: @report_recipients.size)
    end
    true
  end

  # ─── Step 6: Finalize ──────────────────────────────────────

  def generate_progress_reports(ctx, **)
    report = ctx[:support_agent_report]
    return true unless report

    mark_step_running(report, :generate_progress_reports)

    has_failures = report.json_fields["steps"]&.any? { |s| s["status"] == "failed" }
    final_status = has_failures ? "blocked" : "ready"
    failed_step_num = report.json_fields["steps"]&.find { |s| s["status"] == "failed" }&.dig("step")

    mark_step_success(report, :generate_progress_reports, message: "Report saved")
    finalize_report(report, status: final_status, failed_step: failed_step_num)
    true
  end

  # ═══════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════

  # Returns all entities for a fund: the fund entity + child SPVs
  def fund_entities(fund)
    fund_entity = fund.entity
    [fund_entity] + fund_entity.children.to_a
  end

  # ── Calculation helpers ──

  def calculate_for_fund(fund_result)
    fund     = Fund.find(fund_result[:fund_id])
    entities = fund_entities(fund)

    cash_data       = aggregate_cash(fund, entities)
    investment_data = aggregate_investments(fund, entities)
    expense_result  = aggregate_expenses(fund, entities)
    buffer          = fetch_buffer(fund)

    expense_total = expense_result[:total]

    net_position = cash_data[:total] - investment_data[:total] - expense_total - buffer
    daily_outflow = (investment_data[:total] + expense_total).to_f / 90
    runway_days   = daily_outflow.positive? ? (cash_data[:total] / daily_outflow).round : 999

    status = if net_position.negative?
               "shortfall"
             elsif runway_days < 90
               "watch"
             else
               "surplus"
             end

    fund_result.merge!(
      cash_available: cash_data[:total],
      cash_breakdown: cash_data[:breakdown],
      upcoming_investments: investment_data[:total],
      investment_list: investment_data[:list],
      estimated_expenses: expense_total,
      expense_estimation_method: expense_result[:method],
      expense_monthly_predictions: expense_result[:monthly_predictions],
      expense_data_points: expense_result[:data_points],
      buffer_required: buffer,
      net_position: net_position,
      runway_days: runway_days,
      fund_status: status,
      recommended_call: net_position.negative? ? (net_position.abs + buffer) : 0,
      currency: fund.currency
    )
  end

  def aggregate_cash(fund, entities)
    total = 0
    breakdown = []

    entities.each do |entity|
      entries = AccountEntry
                .where(fund_id: fund.id, entity_id: entity.id)
                .fund_entries
                .where(entry_type: @cash_tags)

      latest_date = entries.maximum(:reporting_date)
      next unless latest_date

      entity_cash = entries.where(reporting_date: latest_date).sum(:amount_cents)
      total += entity_cash
      breakdown << { entity_name: entity.name, amount_cents: entity_cash,
                     last_updated: latest_date }
    end

    { total: total, breakdown: breakdown }
  end

  def aggregate_investments(fund, entities)
    total = 0
    list  = []

    entities.each do |entity|
      PortfolioInvestment.proforma
                         .where(fund_id: fund.id, entity_id: entity.id)
                         .where("amount_cents > 0")
                         .find_each do |pi|
                           total += pi.amount_cents
                           list << { name: pi.portfolio_company_name, entity_name: entity.name,
                                     amount_cents: pi.amount_cents, expected_date: pi.investment_date }
                         end
    end

    { total: total, list: list }
  end

  def aggregate_expenses(fund, entities)
    estimator = ExpenseEstimator.new(fund, entities, @expense_tags)
    estimator.estimate(forecast_days: 90)
  end

  def fetch_buffer(fund)
    entries = AccountEntry
              .where(fund_id: fund.id, entity_id: fund.entity_id)
              .fund_entries
              .where(entry_type: @buffer_tags)

    latest_date = entries.maximum(:reporting_date)
    latest_date ? entries.where(reporting_date: latest_date).sum(:amount_cents) : 0
  end
end
