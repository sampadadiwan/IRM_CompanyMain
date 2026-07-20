# frozen_string_literal: true

# Deterministic compliance checker for portfolio companies — validates KPI
# submissions, document presence, and valuation currency. No LLM calls.
#
# @see SupportAgentService
class PortfolioCompanyAgent < SupportAgentService
  DESCRIPTION = "Monitors portfolio companies for KPI submissions, document presence, and valuation accuracy."

  LONG_DESCRIPTION = <<~DESC
    Monitors every portfolio company for data health — KPI submissions, required document presence,
    and valuation accuracy. Runs as a batch across all Portfolio Company investors for the entity.

    Steps:
    • KPI Submission Check — verifies that each portfolio company has submitted KPI reports for
      expected periods. Sends a reminder email if a submission is overdue.
    • Document Presence — checks that all required documents are uploaded for each company.
    • Valuation Check — flags companies missing a valuation or with a stale valuation date.

    Batch processing: runs sequentially per portfolio company; one failure does not block others.
    A batch summary notification is sent after all companies are processed (suppressed for scheduled
    runs). Results are saved as SupportAgentReports and power the portfolio dashboard widget.
  DESC

  # Used when launching for a single portfolio company investor (not a full entity batch).
  SINGLE_LONG_DESCRIPTION = <<~DESC
    Checks data health for this portfolio company — KPI submissions, required document
    presence, and valuation accuracy. Results are saved as a SupportAgentReport and
    displayed on the portfolio dashboard widget.

    Steps:
    • KPI Submission Check — verifies KPI reports have been submitted for expected periods.
    • Document Presence — checks that all required documents are uploaded.
    • Valuation Check — flags a missing or stale valuation entry.
  DESC

  step :initialize_agent
  # == Core Functions ==
  step :check_kpi_submission
  step :send_kpi_reminder
  step :check_document_presence
  step :check_valuations
  step :generate_progress_reports

  def targets(entity_id)
    # Accept either an Investor instance (single target) or an entity_id (return relation)
    if entity_id.is_a?(Investor) || entity_id.is_a?(ActiveRecord::Base)
      [entity_id]
    else
      Investor.where(entity_id: entity_id).where("LOWER(category) = ?", "portfolio company").includes(:kpi_reports, :valuations)
    end
  end

  # Batch processor for PortfolioCompanyAgent — delegates to the shared
  # SupportAgentService.run_batch for progress broadcasting and error handling.
  #
  # @param support_agent_id [Integer]
  # @param targets [Array, ActiveRecord::Relation] Investor records to process
  # @param user_id [Integer, nil] nil for scheduled runs
  # @param entity_id [Integer]
  # @param execution_mode [Symbol] :adhoc_batch or :scheduled
  # @return [Hash] { successes: [...], errors: [...] }
  def self.process_batch(support_agent_id:, targets:, user_id:, entity_id:, with_steps: false, execution_mode: :adhoc_batch)
    targets = targets.includes(:portfolio_kpi_reports, :documents, :valuations) if targets.respond_to?(:includes)

    run_batch(
      support_agent_id: support_agent_id,
      targets: targets,
      user_id: user_id,
      entity_id: entity_id,
      execution_mode: execution_mode
    )
  end

  private

  # Initializes the agent with the portfolio_company under review.
  # Sets up the shared context including issue tracking hashes.
  #
  # @param ctx [Hash] Trailblazer execution context
  # @param target portfolio_company [Investor] record under verification
  def initialize_agent(ctx, target: nil, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :initialize_agent) if report

    super

    portfolio_company = target
    ctx[:portfolio_company] = portfolio_company
    Rails.logger.debug { "[#{self.class.name}] Initializing agent for Investor ID=#{portfolio_company.id}" }
    ctx[:issues] = { kpi_issues: [], document_issues: [], valuation_issues: [] }

    # Returning false here tells Trailblazer to route to the failure track, skipping all
    # subsequent steps. Log explicitly so the silent halt is visible in the run log.
    unless portfolio_company.category&.downcase == "portfolio company"
      Rails.logger.info { "[#{self.class.name}] Skipping Investor ID=#{portfolio_company.id} — category is '#{portfolio_company.category}', expected 'Portfolio Company'" }
      mark_step_failed(report, :initialize_agent, message: "Not a Portfolio Company") if report
      return false
    end

    unless @support_agent.enabled?
      Rails.logger.info { "[#{self.class.name}] Skipping Investor ID=#{portfolio_company.id} — support agent is disabled" }
      mark_step_failed(report, :initialize_agent, message: "Agent is disabled") if report
      return false
    end

    mark_step_success(report, :initialize_agent, message: "Agent initialized") if report
    true
  end

  # Checks whether the portfolio company has submitted last quarter's KPIs.
  # Adds issues to ctx[:issues][:kpi_issues] if submission is missing, incomplete, or delayed.
  #
  # @param ctx [Hash] Trailblazer execution context
  def check_kpi_submission(ctx, portfolio_company: nil, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :check_kpi_submission) if report

    due_period = @support_agent.json_fields["due_period"] || "Quarter"
    days_before_due_period_end = @support_agent.json_fields["days_before_due_period_end"]&.to_i || 15
    due_date = Date.end_of_period(due_period) - days_before_due_period_end.days
    prev_period = Date.previous_end_of_period(due_period, due_date)

    kpi_report = portfolio_company.portfolio_kpi_reports.where(as_of: prev_period..due_date).order(as_of: :desc).last
    @last_kpi_report = kpi_report
    if kpi_report
      ctx[:issues][:kpi_issues] << {
        key: :kpi,
        type: :info,
        message: "Last #{due_period} KPIs submitted on #{kpi_report.as_of}",
        severity: :success
      }
      Rails.logger.debug { "[#{self.class.name}] Last quarter KPIs submitted for Investor ID=#{portfolio_company.id}" }
      mark_step_success(report, :check_kpi_submission, message: "KPIs found") if report
    else
      ctx[:issues][:kpi_issues] << {
        key: :kpi,
        type: :missing,
        message: "Last #{due_period} KPIs not submitted between #{prev_period} and #{due_date}",
        severity: :blocking
      }
      Rails.logger.warn { "[#{self.class.name}] Last quarter KPIs missing for Investor ID=#{portfolio_company.id}" }
      mark_step_failed(report, :check_kpi_submission, message: "KPIs missing") if report
    end
    true
  end

  # Sends a KPI reminder email to the portfolio company when KPIs are missing,
  # but only on configured day-offsets from the period start to avoid daily spam.
  #
  # Configurable via json_fields:
  #   send_kpi_reminder — "true"/"false" (default true)
  #   reminder_days     — comma-separated offsets from period start, e.g. "7,14,21"
  #   due_period        — reporting period, e.g. "Quarter" (shared with check_kpi_submission)
  def send_kpi_reminder(ctx, portfolio_company:, support_agent:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :send_kpi_reminder) if report

    unless enabled?("send_kpi_reminder")
      Rails.logger.debug { "[#{self.class.name}] KPI reminder disabled, skipping." }
      mark_step_skipped(report, :send_kpi_reminder, message: "Disabled") if report
      return true
    end

    kpi_missing = ctx[:issues][:kpi_issues].any? { |i| i[:severity] == :blocking }
    unless kpi_missing
      ctx[:issues][:kpi_issues] << {
        key: :reminder, type: :info,
        message: "KPIs submitted — no reminder needed", severity: :success
      }
      mark_step_skipped(report, :send_kpi_reminder, message: "KPIs submitted — no reminder needed") if report
      return true
    end

    due_period    = support_agent.json_fields["due_period"] || "Quarter"
    reminder_days = support_agent.json_fields["reminder_days"]
                                 &.split(",")&.map(&:to_i) || [7, 14, 21]
    # Use Time.zone.today so period boundaries are evaluated in the Rails application
    # timezone, not the OS system timezone (Date.today). Avoids off-by-one-day errors
    # for deployments where server UTC offset differs from the configured app timezone.
    today         = Time.zone.today
    period_start  = case due_period.downcase
                    when "month"   then today.beginning_of_month
                    when "year"    then today.beginning_of_year
                    else                today.beginning_of_quarter
                    end
    days_elapsed  = (today - period_start).to_i

    unless reminder_days.include?(days_elapsed)
      ctx[:issues][:kpi_issues] << {
        key: :reminder, type: :info,
        message: "Reminder not due today (day #{days_elapsed}; fires on days #{reminder_days.join(', ')})",
        severity: :success
      }
      return true
    end

    # Avoid double-sending on the same calendar day
    last_report = SupportAgentReport
                  .where(owner: portfolio_company, support_agent: support_agent)
                  .order(created_at: :desc).first
    last_sent = last_report&.json_fields&.dig("last_kpi_reminder_sent_at")
    if last_sent && Date.parse(last_sent) >= Time.zone.today
      ctx[:issues][:kpi_issues] << {
        key: :reminder, type: :info, message: "Reminder already sent today", severity: :success
      }
      return true
    end

    EntityMailer.with(
      entity_id: portfolio_company.entity_id,
      requesting_entity_id: support_agent.entity_id
    ).kpi_reminder.deliver_later

    ctx[:last_kpi_reminder_sent_at] = Time.zone.today.iso8601
    ctx[:issues][:kpi_issues] << {
      key: :reminder, type: :info,
      message: "KPI reminder sent (day #{days_elapsed} of #{due_period})", severity: :success
    }
    Rails.logger.info { "[#{self.class.name}] KPI reminder sent for Investor ID=#{portfolio_company.id}" }
    mark_step_success(report, :send_kpi_reminder, message: "Reminder sent") if report
    true
  end

  # Verifies if mandatory documents are present for compliance and operational checks.
  # Adds issues to ctx[:issues][:document_issues] if any required documents are missing or invalid.
  def check_document_presence(ctx, support_agent:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :check_document_presence) if report

    # Guard: skip document check when there is no KPI report to check against.
    # @last_kpi_report is nil when check_kpi_submission found no submission for the
    # period; passing nil as model: would trigger the base class "No record found"
    # blocking issue, which is misleading and duplicates the KPI blocking issue.
    if @last_kpi_report.nil?
      mark_step_skipped(report, :check_document_presence, message: "No KPI report to check against") if report
      return true
    end

    ctx[:check_all_docs] = true
    super(ctx, model: @last_kpi_report, support_agent: support_agent)
    mark_step_success(report, :check_document_presence, message: "Documents checked") if report
    true
  end

  # Validates valuations reported for the portfolio_company.
  # Adds issues to ctx[:issues][:valuation_issues] if there are missing valuations, stale entries, or anomalies.
  #
  # @param ctx [Hash] Trailblazer execution context
  def check_valuations(ctx, portfolio_company: nil, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :check_valuations) if report

    valuation_period = @support_agent.json_fields["valuation_period"] || "Quarter"
    days_before_valuation_period_end = @support_agent.json_fields["days_before_valuation_period_end"]&.to_i || 15
    valuation_due_date = Date.end_of_period(valuation_period) - days_before_valuation_period_end.days
    prev_valuation_period = Date.previous_end_of_period(valuation_period, valuation_due_date)

    valuation = portfolio_company.valuations.where(valuation_date: prev_valuation_period..valuation_due_date).order(valuation_date: :desc).last
    if valuation
      ctx[:issues][:valuation_issues] << {
        key: :valuation,
        type: :info,
        message: "Recent valuation reported on #{valuation.valuation_date}",
        severity: :success
      }
      Rails.logger.debug { "[#{self.class.name}] Recent valuations found for Investor ID=#{portfolio_company.id}" }
      mark_step_success(report, :check_valuations, message: "Valuation found") if report
    else
      ctx[:issues][:valuation_issues] << {
        key: :valuation,
        type: :missing,
        message: "No valuations in the #{valuation_period} between #{prev_valuation_period} and #{valuation_due_date}",
        severity: :blocking
      }
      Rails.logger.warn { "[#{self.class.name}] Missing valuations for Investor ID=#{portfolio_company.id}" }
      mark_step_failed(report, :check_valuations, message: "Valuations missing") if report
    end
    true
  end

  # Generates per-investor/fund reports summarizing issues and state.
  # Stores report as persisted SupportAgentReport record.
  #
  # Called for both single-company (with steps) and batch (adhoc/scheduled) runs.
  # Batch coordination (looping, chart job, notifications) is handled by process_batch.
  def generate_progress_reports(ctx, support_agent:, portfolio_company: nil, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :generate_progress_reports) if report

    super(ctx, model: portfolio_company, support_agent: support_agent)

    # Persist the reminder timestamp directly into json_fields AFTER super saves the
    # report, so it lands at the top level where the duplicate-send guard reads it via
    # json_fields.dig("last_kpi_reminder_sent_at"). Writing it into ctx[:issues] before
    # super would add a String-valued key to an Array-valued hash, causing each_value's
    # reject! cleanup loop in the base class to raise NoMethodError (String#reject!
    # is not defined in Ruby 3.x).
    if ctx[:last_kpi_reminder_sent_at]
      report_obj = ctx[:support_agent_report] || report
      if report_obj
        report_obj.json_fields["last_kpi_reminder_sent_at"] = ctx[:last_kpi_reminder_sent_at]
        report_obj.json_fields_will_change!
        report_obj.save
      end
    end

    mark_step_success(report, :generate_progress_reports, message: "Report saved") if report

    has_blocking = ctx[:issues]&.values&.flatten&.any? { |issue| issue[:severity] == :blocking }
    finalize_report(report, status: has_blocking ? "blocked" : "ready") if report

    broadcast_portco_row(target: portfolio_company)
    true
  end

  def broadcast_portco_row(target:)
    target.broadcast_row(row_template: "investors/portfolio_agent_run_row")
  end
end
