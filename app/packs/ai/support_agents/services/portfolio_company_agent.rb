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
      the most recently completed period (look-back window).
    • Document Presence — checks that all required documents are uploaded for each company.
    • Valuation Check — flags companies missing a valuation or with a stale valuation date.
    • Send Reminders — sends a consolidated reminder listing only the missing items
      (KPIs, documents, valuations) for each company. Skipped when everything is submitted.

    Batch processing: runs sequentially per portfolio company; one failure does not block others.
    A batch summary notification is sent after all companies are processed (suppressed for scheduled
    runs). Results are saved as SupportAgentReports and power the portfolio dashboard widget.
  DESC

  SINGLE_LONG_DESCRIPTION = <<~DESC
    Checks data health for this portfolio company — KPI submissions, required document
    presence, and valuation accuracy. Results are saved as a SupportAgentReport and
    displayed on the portfolio dashboard widget.

    Steps:
    • KPI Submission Check — verifies KPI reports have been submitted for the most recently completed period.
    • Document Presence — checks that all required documents are uploaded.
    • Valuation Check — flags a missing or stale valuation entry.
    • Send Reminders — sends a consolidated reminder for any missing items. Skipped when everything is submitted.
  DESC

  step :initialize_agent
  # Ordering matters: all three checks must run before send_kpi_reminder
  # so ctx[:issues] is fully populated and the consolidated reminder
  # email can list exactly which items (KPIs, documents, valuations) are missing.
  step :check_kpi_submission
  step :check_document_presence
  step :check_valuations
  step :send_kpi_reminder
  step :generate_progress_reports

  def targets(entity_id)
    # Accept either an Investor instance (single target) or an entity_id (return relation)
    if entity_id.is_a?(Investor) || entity_id.is_a?(ActiveRecord::Base)
      [entity_id]
    else
      Investor.where(entity_id: entity_id).where("LOWER(category) = ?", "portfolio company").includes(:kpi_reports, :valuations)
    end
  end

  # Runs the agent across all portfolio companies in batch mode.
  #
  # For scheduled runs, checks the active window gate first — if today is
  # outside T+start to T+end, the entire batch is skipped silently. This
  # prevents checking when companies haven't had time to submit (before T+start)
  # or when the reminder deadline has passed (after T+end).
  #
  # Adhoc runs (Run Now from dashboard, support agents page, or investor page)
  # bypass the window gate — the FM intentionally triggered the run.
  #
  # @param support_agent_id [Integer] the PortfolioCompanyAgent's SupportAgent record ID
  # @param targets [ActiveRecord::Relation] portfolio company Investor records
  # @param user_id [Integer] the FM who triggered the run
  # @param entity_id [Integer] the entity scope
  # @param with_steps [Boolean] whether to show step-by-step progress UI
  # @param execution_mode [Symbol] :adhoc_batch, :single_company_with_steps, or :scheduled
  # @param check_as_on_date [Date, nil] manual period-end date override from dashboard dropdown
  # @return [Hash, nil] { successes: [...], errors: [...] } or nil if skipped
  def self.process_batch(support_agent_id:, targets:, user_id:, entity_id:, with_steps: false, execution_mode: :adhoc_batch, check_as_on_date: nil)
    # Window gate: scheduled runs skip if outside T+start..T+end.
    # Adhoc runs always proceed regardless of window.
    if execution_mode == :scheduled
      support_agent = SupportAgent.find(support_agent_id)
      agent_instance = new
      agent_instance.instance_variable_set(:@support_agent, support_agent)
      unless agent_instance.send(:within_active_window?)
        period_info = agent_instance.send(:compute_check_period)
        Rails.logger.info { "[PortfolioCompanyAgent] Skipping scheduled run — outside active window (#{period_info[:window_start]}..#{period_info[:window_end]}), today is #{Time.zone.today}" }
        return nil
      end
    end

    targets = targets.includes(:portfolio_kpi_reports, :documents, :valuations) if targets.respond_to?(:includes)

    # When check_as_on_date is nil, delegate to the shared run_batch (which loops
    # targets and calls .wtf? without any extra ctx keys — standard flow).
    # When check_as_on_date is present (FM selected a specific period from the
    # dashboard dropdown), we run a custom batch loop that injects check_as_on_date
    # into the Trailblazer ctx so check_kpi_submission uses it instead of auto-computing.
    # This avoids modifying the shared run_batch in support_agent_service.rb.
    if check_as_on_date.present?
      run_batch_with_check_date(
        support_agent_id: support_agent_id,
        targets: targets,
        user_id: user_id,
        entity_id: entity_id,
        execution_mode: execution_mode,
        check_as_on_date: check_as_on_date
      )
    else
      run_batch(
        support_agent_id: support_agent_id,
        targets: targets,
        user_id: user_id,
        entity_id: entity_id,
        execution_mode: execution_mode
      )
    end
  end

  # Custom batch loop that injects check_as_on_date into the Trailblazer ctx.
  #
  # This mirrors SupportAgentService.run_batch (the shared batch loop), but adds
  # check_as_on_date: to the .wtf? call so that check_kpi_submission reads the
  # FM-selected period-end date from ctx[:check_as_on_date] instead of auto-computing.
  #
  # Why not modify run_batch directly? Because run_batch lives in the shared
  # SupportAgentService used by ALL agent types. Adding agent-specific params
  # there would violate the framework's contract. This override keeps the change
  # scoped to PortfolioCompanyAgent only.
  #
  # The loop logic (progress broadcasting, error handling, batch summary) is
  # intentionally kept 1:1 with run_batch so behavior is identical — only the
  # extra ctx key differs.
  #
  # @param support_agent_id [Integer] the SupportAgent record ID
  # @param targets [Array<Investor>, ActiveRecord::Relation] portfolio companies to check
  # @param user_id [Integer] the FM who triggered the run
  # @param entity_id [Integer] the entity scope
  # @param execution_mode [Symbol] :adhoc_batch or :scheduled
  # @param check_as_on_date [Date] the period-end date selected from the dashboard dropdown
  # @return [Hash] { successes: [...], errors: [...] }
  def self.run_batch_with_check_date(support_agent_id:, targets:, user_id:, entity_id:, check_as_on_date:, execution_mode: :adhoc_batch)
    support_agent = SupportAgent.find(support_agent_id)
    targets_array = targets.to_a
    total = targets_array.size

    successes = []
    errors = []

    targets_array.each_with_index do |target, index|
      target_name = target.try(:investor_name) || target.try(:name) || "ID=#{target.id}"

      # Broadcast progress to the Turbo Stream channel so the dashboard
      # shows "Processing 3/15: Company Name" in real time.
      broadcast_batch_progress(
        support_agent: support_agent,
        current: index + 1,
        total: total,
        target_name: target_name,
        user_id: user_id,
        successes: successes.size,
        errors: errors.size
      )

      # Key difference from run_batch: check_as_on_date is injected into the
      # Trailblazer ctx so check_kpi_submission uses the FM-selected period
      # instead of auto-computing the most recently completed period.
      result = support_agent.agent.wtf?(
        support_agent_id: support_agent_id,
        target: target,
        user_id: user_id,
        entity_id: entity_id,
        batch_mode: true,
        check_as_on_date: check_as_on_date
      )

      if result.failure?
        Rails.logger.warn { "#{support_agent.agent_type}.run_batch_with_check_date pipeline failure for Target ID=#{target.id}" }
        errors << { target_id: target.id, target_name: target_name, error: "Pipeline failure (step returned false)" }
      else
        successes << { id: target.id, name: target_name }
      end
    rescue StandardError => e
      Rails.logger.error { "#{support_agent.agent_type}.run_batch_with_check_date error for Target ID=#{target.id}: #{e.message}" }
      Rails.logger.error { e.backtrace.join("\n") }
      errors << { target_id: target.id, target_name: target_name, error: e.message }
    end

    # Signal the Turbo Stream that the batch is complete (triggers page reload on dashboard).
    broadcast_batch_complete(
      support_agent: support_agent,
      user_id: user_id,
      successes: successes.size,
      errors: errors.size,
      total: total
    )

    # Send batch summary notification to the FM (skipped for scheduled runs).
    if execution_mode != :scheduled
      begin
        batch_target_type = targets_array.first.class.name if targets_array.any?
        SupportAgentJob.new.send(:send_batch_summary, support_agent, successes, errors, user_id, batch_target_type) if defined?(SupportAgentJob)
      rescue StandardError => e
        Rails.logger.error { "#{support_agent.agent_type}.run_batch_with_check_date: failed to send batch summary: #{e.message}" }
      end
    end

    { successes: successes, errors: errors }
  end

  # Setup health check — the reminder toggle fails closed, so an unset value
  # silently disables reminders. (Reminder cadence needs no check: reminders
  # fire on every run within the active window, and the window settings all
  # have sane defaults when missing.)
  def self.config_issues(support_agent)
    missing_toggle_issues(support_agent, { "send_kpi_reminder" => "KPI submission reminder emails" })
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

  # Checks whether the portfolio company has submitted KPI reports for the
  # look-back period (the most recently completed reporting period).
  #
  # Uses compute_check_period to determine which period to validate. Queries
  # portfolio_kpi_reports where as_of falls within the period's date range
  # (e.g., April 1 – June 30 for Q2). A range match is used rather than an
  # exact date match because companies may tag reports with any date within
  # the period, not necessarily the exact period-end date.
  #
  # Stores the period_info hash in ctx[:period_info] so downstream steps
  # (check_document_presence, check_valuations, send_kpi_reminder) can reuse
  # the same computed period without recalculating.

  #
  # @param ctx [Hash] Trailblazer context — receives :period_info and :issues updates
  # @param portfolio_company [Investor] the portfolio company being checked
  # @param support_agent_report [SupportAgentReport, nil] report for step-by-step UI progress
  # @return [Boolean] always true (issues are recorded in ctx, not via return value)
  def check_kpi_submission(ctx, portfolio_company: nil, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :check_kpi_submission) if report

    # Compute the look-back period. Uses ctx[:check_as_on_date] when the FM
    # runs adhoc with a manual period selection from the dashboard dropdown.
    period_info = compute_check_period(check_as_on_date: ctx[:check_as_on_date])
    ctx[:period_info] = period_info

    # Query for KPI reports with as_of in the period's date range.
    # Range match (not exact): any report tagged within Q2 (Apr 1 – Jun 30) counts.
    # Ordered desc to get the most recent report first.
    kpi_report = portfolio_company.portfolio_kpi_reports
                                  .where(as_of: period_info[:period_start]..period_info[:period_end])
                                  .order(as_of: :desc)
                                  .first

    # Store for downstream steps — check_document_presence uses this to verify
    # that documents are attached to the KPI report.
    @last_kpi_report = kpi_report

    if kpi_report
      ctx[:issues][:kpi_issues] << {
        key: :kpi,
        type: :info,
        message: "#{period_info[:period_label]} KPIs submitted (as_of: #{kpi_report.as_of})",
        severity: :success
      }
      Rails.logger.debug { "[#{self.class.name}] #{period_info[:period_label]} KPIs found for Investor ID=#{portfolio_company.id} (as_of: #{kpi_report.as_of})" }
      mark_step_success(report, :check_kpi_submission, message: "KPIs found for #{period_info[:period_label]}") if report
    else
      ctx[:issues][:kpi_issues] << {
        key: :kpi,
        type: :missing,
        message: "#{period_info[:period_label]} KPIs not submitted (expected as_of between #{period_info[:period_start]} and #{period_info[:period_end]})",
        severity: :blocking
      }
      Rails.logger.warn { "[#{self.class.name}] #{period_info[:period_label]} KPIs missing for Investor ID=#{portfolio_company.id} (checked #{period_info[:period_start]}..#{period_info[:period_end]})" }
      mark_step_failed(report, :check_kpi_submission, message: "KPIs missing for #{period_info[:period_label]}") if report
    end
    true
  end

  # Sends a consolidated reminder email listing all missing items (KPIs,
  # documents, valuations) for the look-back period.
  #
  # Runs after all three checks so ctx[:issues] is fully populated.
  # Checks each category for :blocking issues and builds a missing_items
  # list. Sends one email per company listing only what's missing.
  # Skipped when everything is submitted.
  #
  # Deduplication: prevents double-sending on the same calendar day by
  # checking last_kpi_reminder_sent_at in the previous report's json_fields.
  #
  # @param ctx [Hash] Trailblazer context — reads :issues and :period_info
  # @param portfolio_company [Investor] the portfolio company being checked
  # @param support_agent [SupportAgent] the agent configuration record
  # @param support_agent_report [SupportAgentReport, nil] report for step progress UI
  # @return [Boolean] always true (issues are recorded in ctx, not via return value)
  def send_kpi_reminder(ctx, portfolio_company:, support_agent:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :send_kpi_reminder) if report

    # Guard: check if reminders are enabled via json_fields toggle.
    unless enabled?("send_kpi_reminder")
      Rails.logger.debug { "[#{self.class.name}] Reminders disabled, skipping." }
      mark_step_skipped(report, :send_kpi_reminder, message: "Disabled") if report
      return true
    end

    # Build the list of missing items across all three categories.
    missing_items = []
    missing_items << "KPIs" if ctx[:issues][:kpi_issues].any? { |i| i[:severity] == :blocking }
    missing_items << "Documents" if ctx[:issues][:document_issues].any? { |i| i[:severity] == :blocking }
    missing_items << "Valuations" if ctx[:issues][:valuation_issues].any? { |i| i[:severity] == :blocking }

    # Guard: no reminder needed if everything is submitted.
    if missing_items.empty?
      ctx[:issues][:kpi_issues] << {
        key: :reminder, type: :info,
        message: "All items submitted — no reminder needed", severity: :success
      }
      mark_step_skipped(report, :send_kpi_reminder, message: "All items submitted — no reminder needed") if report
      return true
    end

    # Guard: prevent double-sending on the same calendar day.
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

    # Send consolidated reminder with the missing items list.
    period_info = ctx[:period_info]
    EntityMailer.with(
      entity_id: portfolio_company.entity_id,
      requesting_entity_id: support_agent.entity_id,
      missing_items: missing_items,
      period_label: period_info&.dig(:period_label)
    ).kpi_reminder.deliver_later

    ctx[:last_kpi_reminder_sent_at] = Time.zone.today.iso8601
    ctx[:issues][:kpi_issues] << {
      key: :reminder, type: :info,
      message: "Reminder sent for #{period_info&.dig(:period_label) || 'current period'} — missing: #{missing_items.join(', ')}",
      severity: :success
    }
    Rails.logger.info { "[#{self.class.name}] Reminder sent for Investor ID=#{portfolio_company.id} (#{period_info&.dig(:period_label)}) — missing: #{missing_items.join(', ')}" }
    mark_step_success(report, :send_kpi_reminder, message: "Reminder sent (#{missing_items.join(', ')})") if report
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

  # Validates whether a valuation exists for the look-back period.
  #
  # Uses the same period_info computed by check_kpi_submission (stored in
  # ctx[:period_info]) so KPIs and valuations are checked against the same
  # date range. This replaces the old separate valuation_period /
  # days_before_valuation_period_end settings — one unified period for all checks.
  #
  # Queries valuations where valuation_date falls within the period's date range
  # (e.g., April 1 – June 30 for Q2). Range match, same as KPI reports.
  #
  # @param ctx [Hash] Trailblazer context — reads :period_info set by check_kpi_submission
  # @param portfolio_company [Investor] the portfolio company being checked
  # @param support_agent_report [SupportAgentReport, nil] report for step-by-step UI progress
  # @return [Boolean] always true (issues are recorded in ctx, not via return value)
  def check_valuations(ctx, portfolio_company: nil, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :check_valuations) if report

    # Reuse the same period computed by check_kpi_submission.
    # Fallback to compute_check_period if check_kpi_submission hasn't run
    # (shouldn't happen in normal flow, but guards against step reordering).
    period_info = ctx[:period_info] || compute_check_period(check_as_on_date: ctx[:check_as_on_date])

    # Query for valuations with valuation_date in the period's date range.
    # Range match: any valuation dated within Q2 (Apr 1 – Jun 30) counts.
    valuation = portfolio_company.valuations
                                 .where(valuation_date: period_info[:period_start]..period_info[:period_end])
                                 .order(valuation_date: :desc)
                                 .first

    if valuation
      ctx[:issues][:valuation_issues] << {
        key: :valuation,
        type: :info,
        message: "#{period_info[:period_label]} valuation reported on #{valuation.valuation_date}",
        severity: :success
      }
      Rails.logger.debug { "[#{self.class.name}] #{period_info[:period_label]} valuation found for Investor ID=#{portfolio_company.id} (date: #{valuation.valuation_date})" }
      mark_step_success(report, :check_valuations, message: "Valuation found for #{period_info[:period_label]}") if report
    else
      ctx[:issues][:valuation_issues] << {
        key: :valuation,
        type: :missing,
        message: "#{period_info[:period_label]} valuation missing (expected valuation_date between #{period_info[:period_start]} and #{period_info[:period_end]})",
        severity: :blocking
      }
      Rails.logger.warn { "[#{self.class.name}] #{period_info[:period_label]} valuation missing for Investor ID=#{portfolio_company.id} (checked #{period_info[:period_start]}..#{period_info[:period_end]})" }
      mark_step_failed(report, :check_valuations, message: "Valuation missing for #{period_info[:period_label]}") if report
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

  # Computes the look-back period for data validation.
  #
  # Instead of checking the current in-progress period (which has no data yet),
  # this finds the most recently completed period and derives:
  # - The date range to query for KPIs/valuations (period_start..period_end)
  # - The active window (T+start to T+end) during which the agent should run
  #
  # The "T" in T+start / T+end refers to the period-end date (check_date).
  # For example, with period=Quarterly and today=July 21:
  #   check_date   = June 30 (last completed quarter)
  #   period_start = April 1
  #   period_end   = June 30
  #   window_start = July 15 (T+15)
  #   window_end   = August 29 (T+60)
  #
  # Reads new json_fields keys (start_days_after_period_end, end_days_after_period_end)
  # with fallback to the legacy key (days_before_due_period_end) for backward compatibility
  # during the transition period while old custom form fields are still present.
  #
  # @param check_as_on_date [Date, nil] explicit period-end date for adhoc runs;
  #   when nil, auto-computes the most recently completed period
  # @return [Hash] period computation result with keys:
  #   :check_date   [Date]   — the period-end date being validated (e.g., June 30)
  #   :window_start [Date]   — first day the agent should run (e.g., July 15)
  #   :window_end   [Date]   — last day the agent should run (e.g., August 29)
  #   :period_start [Date]   — start of the data range to query (e.g., April 1)
  #   :period_end   [Date]   — end of the data range to query (e.g., June 30)
  #   :period_label [String] — human-readable label (e.g., "Q2 2026")
  def compute_check_period(check_as_on_date: nil)
    period = @support_agent.json_fields["due_period"] || "Quarter"

    # New field names with fallback to legacy field name during transition.
    # Once the old custom form fields are removed, the fallback can be dropped.
    start_days = (
      @support_agent.json_fields["start_days_after_period_end"] ||
      @support_agent.json_fields["days_before_due_period_end"] ||
      15
    ).to_i
    end_days = (@support_agent.json_fields["end_days_after_period_end"] || 60).to_i

    # Step 1: Determine the period-end date to validate against.
    # For adhoc runs, the FM can override this via the dashboard dropdown.
    # For scheduled runs, auto-compute the most recently completed period.
    check_date = if check_as_on_date.present?
                   check_as_on_date.to_date
                 else
                   Date.previous_end_of_period(period)
                 end

    # Step 2: Active window — the date range during which scheduled runs execute.
    # Before window_start: too early, companies haven't had time to submit.
    # After window_end: deadline passed, stop sending reminders.
    window_start = check_date + start_days.days
    window_end   = check_date + end_days.days

    # Step 3: Data query range — the period we're checking data for.
    # e.g., for Q2 ending June 30: period_start=April 1, period_end=June 30.
    # KPI reports and valuations with as_of/valuation_date in this range are valid.
    period_start = Date.previous_end_of_period(period, check_date) + 1.day
    period_end   = check_date

    # Step 4: Human-readable label for messages and UI display.
    period_label = case period.to_s.downcase
                   when "month"
                     check_date.strftime("%B %Y") # e.g., "June 2026"
                   when "quarter"
                     quarter_num = ((check_date.month - 1) / 3) + 1
                     "Q#{quarter_num} #{check_date.year}" # e.g., "Q2 2026"
                   when "half year", "half_year", "halfyear"
                     check_date.month <= 6 ? "H1 #{check_date.year}" : "H2 #{check_date.year}"
                   when "year"
                     check_date.year.to_s # e.g., "2026"
                   else
                     period
                   end

    {
      check_date: check_date,
      window_start: window_start,
      window_end: window_end,
      period_start: period_start,
      period_end: period_end,
      period_label: period_label
    }
  end

  # Determines whether today falls within the active checking window
  # (T+start to T+end) for the most recently completed period.
  #
  # Used as a gate for scheduled (cron) runs only. When the agent runs
  # on schedule and today is outside the window, the run is skipped silently
  # to avoid checking when companies haven't had time to submit (before T+start)
  # or when the deadline has passed (after T+end).
  #
  # Adhoc runs (Run Now button from dashboard, support agents page, or
  # investor page) bypass this gate entirely — the FM intentionally triggered
  # the run and expects results regardless of the window.
  #
  # @return [Boolean] true if today is between window_start and window_end
  # @see compute_check_period
  def within_active_window?
    period_info = compute_check_period
    today = Time.zone.today
    today.between?(period_info[:window_start], period_info[:window_end])
  end

  def broadcast_portco_row(target:)
    target.broadcast_row(row_template: "investors/portfolio_agent_run_row")
  end
end
