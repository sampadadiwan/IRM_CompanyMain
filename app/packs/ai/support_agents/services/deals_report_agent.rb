# frozen_string_literal: true

# Analyzes all open deals for an entity and generates a fundraising status report.
#
# DealsReportAgent iterates over configured (or all open) deals, calculates
# per-deal fundraising summaries (committed, pending, declined, fill rate,
# investor pipeline by activity step), saves an HTML report to the Deal's
# document folder, and emails it to configured recipients.
#
# Config keys (json_fields on SupportAgent):
#   deal_ids         — comma-separated Deal IDs to include (blank = all Open deals)
#   report_recipients — comma-separated email addresses
#   stale_days       — integer; deals with no investor activity in N days are flagged (default: 30)
#
# @example
#   DealsReportAgent.call(support_agent_id: 1, target: entity, user_id: 10)
#
# @see SupportAgentService
# @see DealsReportRenderer
class DealsReportAgent < SupportAgentService
  DESCRIPTION = "Analyzes all open deals for an entity and generates a fundraising status report with per-deal summaries."

  LONG_DESCRIPTION = <<~DESC
    Iterates over all open deals (or a configured subset) and produces a detailed
    fundraising status report for each deal. Results are saved as individual
    SupportAgentReport records per deal and an email summary is sent to configured
    recipients.

    Per-deal analysis includes:
    • Fundraising targets vs committed, pending, and declined amounts.
    • Fill rate percentage and deal health classification (on_track / needs_attention).
    • Activity step distribution — how many investors are at each pipeline stage.
    • Top investors ranked by committed amount.
    • Staleness detection — deals flagged when no investor activity occurs past the
      configured threshold (default: 30 days).

    Configuration via json_fields:
    • deal_ids — comma-separated Deal IDs (blank = all Open deals).
    • report_recipients — comma-separated email addresses for the summary email.
    • stale_days — integer threshold for staleness detection (default: 30).
    • Content flags: include_greeting, include_updates, include_tasks_due,
      include_tasks_overdue, include_stale_items (all default true).
  DESC

  STEP_LABELS = {
    initialize_agent: "Initialize",
    load_deals: "Load Deals",
    calculate_deal_summary: "Calculate Summaries",
    generate_deal_reports: "Generate Reports",
    send_report_email: "Send Email",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :load_deals
  step :calculate_deal_summary
  step :generate_deal_reports
  step :send_report_email
  step :generate_progress_reports

  # Runs against the entity (organization) itself; iterates over its deals internally.
  def targets(entity_id)
    Entity.where(id: entity_id)
  end

  private

  # ─── Step 1: Initialize ─────────────────────────────────────────────────────

  def initialize_agent(ctx, **)
    super
    @config            = @support_agent.json_fields || {}
    @report_recipients = (@config["report_recipients"] || "").split(",").map(&:strip).compact_blank
    @stale_days        = (@config["stale_days"] || 30).to_i
    @deal_ids          = (@config["deal_ids"] || "").split(",").map { |x| x.strip.to_i }.compact_blank

    # Content flags (default all on for backwards compatibility)
    @include_greeting      = @config.fetch("include_greeting",      "true") == "true"
    @include_updates       = @config.fetch("include_updates",       "true") == "true"
    @include_tasks_due     = @config.fetch("include_tasks_due",     "true") == "true"
    @include_tasks_overdue = @config.fetch("include_tasks_overdue", "true") == "true"
    @include_stale_items   = @config.fetch("include_stale_items",   "true") == "true"

    ctx[:deal_results] = []

    report = ctx[:support_agent_report]
    if report
      mark_step_running(report, :initialize_agent)
      mark_step_success(report, :initialize_agent,
                        message: "Config loaded — stale threshold: #{@stale_days} days")
    end
    true
  end

  # ─── Step 2: Load Deals ─────────────────────────────────────────────────────

  def load_deals(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :load_deals) if report

    entity = @support_agent.entity
    base   = Deal.where(entity_id: entity.id, status: "Open")
    base   = base.where(id: @deal_ids) if @deal_ids.any?

    ctx[:deals] = base.includes(:deal_investors, :deal_activities, :investors).to_a

    if ctx[:deals].empty?
      mark_step_skipped(report, :load_deals, message: "No open deals found") if report
      return true
    end

    if report
      mark_step_success(report, :load_deals,
                        message: "#{ctx[:deals].size} deal(s) loaded",
                        count: ctx[:deals].size)
    end
    true
  end

  # ─── Step 3: Calculate Summaries ────────────────────────────────────────────

  def calculate_deal_summary(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :calculate_deal_summary) if report

    ctx[:deal_results] = ctx[:deals].map { |deal| summarize_deal(deal) }

    if report
      mark_step_success(report, :calculate_deal_summary,
                        message: "Summarized #{ctx[:deal_results].size} deal(s)",
                        count: ctx[:deal_results].size)
    end
    true
  end

  # ─── Step 4: Save Per-Deal HTML Reports ─────────────────────────────────────

  def generate_deal_reports(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :generate_deal_reports) if report

    ctx[:deal_results].each do |deal_result|
      deal = Deal.find_by(id: deal_result[:deal_id])
      next unless deal

      # Persist summary as SupportAgentReport owned by the deal
      deal_report = SupportAgentReport.find_or_initialize_by(
        owner: deal, support_agent: @support_agent
      )
      deal_report.json_fields = deal_result.deep_stringify_keys
      deal_report.status      = :completed
      deal_report.save!

      begin
        DealsReportRenderer.new(deal_result, @support_agent)
                           .save_to_deal_folder(deal, ctx[:user_id])
      rescue StandardError => e
        Rails.logger.error { "[DealsReportAgent] Failed to save report doc for #{deal.name}: #{e.message}" }
      end
    end

    if report
      mark_step_success(report, :generate_deal_reports,
                        message: "Saved #{ctx[:deal_results].size} deal report(s)",
                        count: ctx[:deal_results].size)
    end
    true
  end

  # ─── Step 5: Send Email ──────────────────────────────────────────────────────

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

    DealsReportMailer.with(
      support_agent_id: @support_agent.id,
      deal_results: ctx[:deal_results],
      recipients: @report_recipients,
      include_greeting: @include_greeting,
      include_updates: @include_updates,
      include_tasks_due: @include_tasks_due,
      include_tasks_overdue: @include_tasks_overdue,
      include_stale_items: @include_stale_items
    ).send_report.deliver_later

    if report
      mark_step_success(report, :send_report_email,
                        message: "Queued for #{@report_recipients.size} recipient(s)",
                        count: @report_recipients.size)
    end
    true
  end

  # ─── Step 6: Finalize ────────────────────────────────────────────────────────

  def generate_progress_reports(ctx, **)
    report = ctx[:support_agent_report]
    return true unless report

    mark_step_running(report, :generate_progress_reports)

    has_failures  = report.json_fields["steps"]&.any? { |s| s["status"] == "failed" }
    final_status  = has_failures ? "blocked" : "ready"
    failed_step   = report.json_fields["steps"]&.find { |s| s["status"] == "failed" }&.dig("step")

    mark_step_success(report, :generate_progress_reports, message: "Report saved")
    finalize_report(report, status: final_status, failed_step: failed_step)
    true
  end

  # ═══════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════

  def summarize_deal(deal)
    investors = deal.deal_investors.includes(:investor, :deal_activity)
    active    = investors.select { |di| di.status == "Active" }
    pending   = investors.select { |di| di.status == "Pending" }
    declined  = investors.select { |di| di.status == "Declined" }

    target_cents    = deal.amount_cents.to_i
    committed_cents = active.sum(&:total_amount_cents).to_i
    pending_cents   = pending.sum(&:total_amount_cents).to_i
    declined_cents  = declined.sum(&:total_amount_cents).to_i
    remaining_cents = [target_cents - committed_cents, 0].max

    fill_rate = target_cents.positive? ? ((committed_cents.to_f / target_cents) * 100).round(1) : 0.0

    deal_status = derive_deal_status(fill_rate, deal)

    # Days since any investor activity
    last_activity_at = deal.deal_activities
                           .where.not(deal_investor_id: nil)
                           .maximum(:updated_at)
    stale_days = last_activity_at ? (Time.zone.now - last_activity_at).to_i / 86_400 : nil
    stale      = stale_days.present? && stale_days > @stale_days

    # Activity step distribution: how many investors are at each step
    step_distribution = build_step_distribution(investors, deal)

    # Top investors by amount
    top_investors = active.sort_by { |di| -di.total_amount_cents.to_i }.first(10).map do |di|
      {
        investor_name: di.investor_name,
        status: di.status,
        tier: di.tier,
        total_amount_cents: di.total_amount_cents.to_i,
        current_step: di.deal_activity&.title
      }
    end

    {
      deal_id: deal.id,
      deal_name: deal.name,
      currency: deal.currency,
      deal_status: deal_status,
      target_cents: target_cents,
      committed_cents: committed_cents,
      pending_cents: pending_cents,
      declined_cents: declined_cents,
      remaining_cents: remaining_cents,
      fill_rate: fill_rate,
      total_investors: investors.size,
      active_count: active.size,
      pending_count: pending.size,
      declined_count: declined.size,
      stale: stale,
      stale_days: stale_days,
      last_activity_at: last_activity_at&.iso8601,
      step_distribution: step_distribution,
      top_investors: top_investors
    }
  end

  def derive_deal_status(fill_rate, deal)
    return "closed"   if deal.status == "Closed"
    return "complete" if fill_rate >= 100
    return "on_track" if fill_rate >= 60

    "needs_attention"
  end

  def build_step_distribution(investors, deal)
    templates = DealActivity.where(deal_id: deal.id, status: "template").order(:sequence)
    return [] if templates.empty?

    templates.map do |tmpl|
      count = investors.count { |di| di.deal_activity&.title == tmpl.title }
      { step_title: tmpl.title, investor_count: count, sequence: tmpl.sequence }
    end
  end
end
