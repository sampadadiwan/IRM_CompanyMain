# frozen_string_literal: true

# RtaReconciliationAgent — reconciles an uploaded RTA unit statement PDF against
# CapHive's live fund_units / capital_commitments data.
#
# Scoped to one Fund per run. Accepts an RTA PDF attached as the "RTA Statement (PDF)"
# document on the agent, extracts structured data via LLM, then reconciles at two levels:
#   1. Summary  — total closing units per ISIN (scheme) vs fund.capital_commitments total
#   2. Folio    — each folio's closing units vs capital_commitment.total_fund_units_quantity
#   3. Coverage — every ISIN the fund holds vs which ISINs the statement actually covers
#   4. Movement — RTA-reported subscriptions/redemptions for the period vs CapHive's own
#                 FundUnit ledger for the same period (requires a prior run to anchor the period)
#   5. Continuity — this period's RTA opening balance vs the prior run's RTA closing balance
#
# Multiple ISIN blocks in a single PDF are each reconciled independently.
#
# json_fields configuration:
#   tolerance_units        — float (default 0.01)
#   tolerance_pct          — float (default 0, disabled)
#   check_pending_requests — "Yes"/"No" (default "Yes")
#   send_report            — "Yes"/"No" (default "Yes")
#   notify_email           — string
#   statement_date         — date override string (optional)
#
# @see SupportAgentService
class RtaReconciliationAgent < SupportAgentService
  DESCRIPTION = "Reconciles an RTA unit statement PDF against CapHive fund unit balances at summary and folio level."

  LONG_DESCRIPTION = <<~DESC
    Uploads and parses an RTA (Registrar and Transfer Agent) unit statement PDF, then
    reconciles the extracted figures against CapHive's live capital_commitments data.

    Reconciliation levels:
    • Summary — total closing units per ISIN extracted from the PDF vs the sum of
      capital_commitments.total_fund_units_quantity filtered by unit_type.
    • Folio   — each folio's closing units vs the matching CapitalCommitment's
      total_fund_units_quantity (looked up by folio_id).
    • Reverse — CapHive commitments with a folio_id that are absent from the PDF.

    Supports PDFs with multiple ISIN blocks (unit classes). Each scheme is reconciled
    independently — a break in one scheme does not skip others.

    Results are stored in a SupportAgentReport owned by the Fund and optionally emailed.
  DESC

  STEP_LABELS = {
    initialize_agent: "Initialize",
    check_unit_reconciliation_readiness: "Fund Readiness",
    parse_rta_statement: "Parse Statement",
    reconcile_schemes: "Reconcile",
    check_scheme_coverage: "Coverage Check",
    check_pending_requests: "Pending Requests",
    send_reconciliation_report: "Send Report",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :check_unit_reconciliation_readiness
  step :parse_rta_statement
  step :reconcile_schemes
  step :check_scheme_coverage
  step :check_pending_requests
  step :send_reconciliation_report
  step :generate_progress_reports

  # Runs against the single Fund the agent is triggered for.
  def targets(entity_id)
    Fund.where(entity_id: entity_id)
  end

  # Human descriptions of the steps each json_fields toggle gates.
  CHECK_TOGGLES = {
    "send_report"            => "the reconciliation report email",
    "check_pending_requests" => "the pending unit-request check"
  }.freeze

  # Setup health check — unset tolerances mean zero tolerance (every rounding
  # difference becomes a break), and unit types without an ISIN are invisible
  # to reconciliation entirely.
  def self.config_issues(support_agent)
    fields = support_agent.json_fields || {}
    issues = missing_toggle_issues(support_agent, CHECK_TOGGLES)

    if toggle_on?(support_agent, "send_report") && fields["notify_email"].to_s.strip.blank?
      issues << "'send_report' is enabled but 'notify_email' is blank — the reconciliation report will never be emailed."
    end

    if fields["tolerance_units"].to_s.strip.blank? && fields["tolerance_pct"].to_s.strip.blank?
      issues << "No reconciliation tolerance configured ('tolerance_units' / 'tolerance_pct') — tolerance is zero, so every rounding difference will be reported as a break."
    end

    # Unit settings that exist but lack an ISIN cannot be matched to RTA statement schemes
    FundUnitSetting.joins(:fund)
                   .where(funds: { entity_id: support_agent.entity_id })
                   .where(isin: [nil, ""])
                   .includes(:fund).find_each do |fus|
      issues << "Unit type '#{fus.name}' of fund '#{fus.fund.name}' has no ISIN configured — it cannot be reconciled by this agent."
    end

    issues
  end

  private

  def initialize_agent(ctx, target:, rta_pdf_document_id: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :initialize_agent) if report
    super
    ctx[:fund] = target
    ctx[:scheme_results] = []
    ctx[:issues]         = []
    ctx[:extracted]      = nil
    ctx[:target_model]   = target
    ctx[:rta_pdf_document_id] = rta_pdf_document_id
    # Captured before this run creates its own row, so it reliably resolves to
    # the previous run's saved results (used for opening-balance continuity
    # and as the start of the movement-reconciliation period).
    ctx[:previous_report] = SupportAgentReport.find_by(owner: target, support_agent: @support_agent, latest: true)
    mark_step_success(report, :initialize_agent) if report
    true
  end

  # Fund-wide configuration check — independent of any uploaded statement.
  # check_scheme_coverage (below) only ever looks at unit types that already have an
  # ISIN configured in FundUnitSetting, so a unit type with real commitments but no
  # FundUnitSetting/ISIN at all is invisible to every other check in this agent. This
  # step exists specifically to surface that blind spot before any statement is parsed.
  def check_unit_reconciliation_readiness(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_unit_reconciliation_readiness) if report

    fund = ctx[:fund]
    base = fund.capital_commitments.where.not(unit_type: [nil, ""]).where.not(total_fund_units_quantity: 0)
    folio_counts = base.group(:unit_type).count
    unit_sums    = base.group(:unit_type).sum(:total_fund_units_quantity)

    readiness = folio_counts.keys.map do |unit_type|
      fus = FundUnitSetting.find_by(fund: fund, name: unit_type)
      isin_configured = fus&.isin.present?
      folio_count = folio_counts[unit_type]
      units       = unit_sums[unit_type].to_f.round(8)

      unless isin_configured
        ctx[:issues] << { type: :blocking,
                          message: "Unit type #{unit_type}: #{folio_count} folio(s), #{units} units — " \
                                    "#{fus ? 'FundUnitSetting exists but has no ISIN' : 'no FundUnitSetting configured'} " \
                                    "— cannot be reconciled by this agent",
                          severity: :blocking }
      end

      { unit_type: unit_type, folio_count: folio_count, units: units,
        fund_unit_setting_configured: fus.present?, isin: fus&.isin, isin_configured: isin_configured }
    end

    ctx[:unit_readiness] = readiness
    missing = readiness.count { |r| !r[:isin_configured] }
    mark_step_success(report, :check_unit_reconciliation_readiness, message: "#{missing} unit type(s) missing ISIN config") if report
    true
  end

  # Reads the PDF attached to the agent, calls the LLM with the generic extraction
  # prompt, validates the returned JSON, and stores it in ctx[:extracted].
  # Records a :blocking issue and returns true (soft-fail) when extraction fails.
  def parse_rta_statement(ctx, rta_pdf_document_id: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :parse_rta_statement) if report

    doc = rta_pdf_document_id.present? ? Document.find_by(id: rta_pdf_document_id) : nil
    if doc.nil? || doc.file.blank?
      ctx[:issues] << { type: :blocking, message: "No RTA statement PDF uploaded. " \
                                                  "Please upload a PDF when running the agent from the Fund page.", severity: :blocking }
      Rails.logger.warn { "[RtaReconciliationAgent] No RTA statement PDF for agent #{@support_agent.id}" }
      mark_step_failed(report, :parse_rta_statement, message: "No PDF uploaded") if report
      return true
    end

    pdf_text = extract_pdf_text(doc)
    if pdf_text.blank?
      ctx[:issues] << { type: :blocking, message: "Could not read text from the uploaded PDF.", severity: :blocking }
      mark_step_failed(report, :parse_rta_statement, message: "Unreadable PDF") if report
      return true
    end

    # Truncate to avoid exceeding LLM context limits
    if pdf_text.length > 30_000
      Rails.logger.warn { "[RtaReconciliationAgent] PDF text truncated from #{pdf_text.length} to 30,000 chars" }
      pdf_text = pdf_text.first(30_000)
    end

    result = ctx[:llm].ask(extraction_prompt(pdf_text))
    raw_json = result.content.to_s.strip

    extracted = JSON.parse(raw_json)
    schemes   = extracted["schemes"]

    if schemes.blank?
      ctx[:issues] << { type: :blocking, message: "LLM returned no scheme data from the PDF.", severity: :blocking }
      mark_step_failed(report, :parse_rta_statement, message: "No schemes extracted") if report
      return true
    end

    ctx[:extracted] = extracted.deep_symbolize_keys
    ctx[:statement_date_str] = statement_date_from(ctx)
    ctx[:statement_date] = normalize_statement_date_obj(ctx[:statement_date_str])
    Rails.logger.info { "[RtaReconciliationAgent] Extracted #{schemes.size} scheme(s) from PDF" }
    mark_step_success(report, :parse_rta_statement, message: "#{schemes.size} scheme(s) extracted") if report
    true
  rescue JSON::ParserError => e
    ctx[:issues] << { type: :blocking, message: "LLM response was not valid JSON: #{e.message}", severity: :blocking }
    Rails.logger.error { "[RtaReconciliationAgent] JSON parse error: #{e.message}" }
    mark_step_failed(report, :parse_rta_statement, message: "Invalid JSON from LLM") if report
    true
  rescue StandardError => e
    # Catches network timeouts, rate-limit errors, and other LLM API failures
    ctx[:issues] << { type: :blocking, message: "Statement extraction failed: #{e.message}", severity: :blocking }
    Rails.logger.error { "[RtaReconciliationAgent] Extraction error: #{e.class}: #{e.message}" }
    mark_step_failed(report, :parse_rta_statement, message: "Extraction error") if report
    true
  end

  # Loops over each extracted scheme (ISIN block) and runs summary + folio reconciliation.
  # Each scheme is independent — a failure in one does not skip others.
  def reconcile_schemes(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :reconcile_schemes) if report

    unless ctx[:extracted]
      mark_step_skipped(report, :reconcile_schemes, message: "Skipped — no extracted data") if report
      return true
    end

    fund    = ctx[:fund]
    schemes = ctx[:extracted][:schemes] || []

    schemes.each do |scheme|
      isin   = scheme[:isin].to_s.strip
      result = { isin: isin, scheme: scheme[:scheme], nav: scheme[:nav] }

      # Validate ISIN against FundUnitSetting
      fus = FundUnitSetting.find_by(fund: fund, isin: isin)
      unless fus
        orphan_folios = scheme[:folios] || []
        orphan_units  = orphan_folios.sum { |f| f[:closing_units].to_f }.round(8)
        result[:status]             = :warning
        result[:orphan_folio_count] = orphan_folios.size
        result[:orphan_units]       = orphan_units
        result[:message] = "ISIN #{isin} not found in FundUnitSetting for this fund — scheme skipped " \
                            "(#{orphan_folios.size} folio(s), #{orphan_units} units in statement)"
        ctx[:scheme_results] << result
        ctx[:issues] << { type: :warning, message: result[:message], severity: :warning }
        Rails.logger.warn { "[RtaReconciliationAgent] #{result[:message]}" }
        next
      end

      result[:fund_unit_setting_id] = fus.id

      # Summary reconciliation
      rta_closing    = scheme.dig(:summary, :closing_units).to_f
      caphive_total  = fund.capital_commitments.where(unit_type: fus.name).sum(:total_fund_units_quantity).to_f
      summary_diff   = (rta_closing - caphive_total).abs
      summary_match  = within_tolerance?(summary_diff, rta_closing, caphive_total)

      result[:extracted_summary] = scheme[:summary]
      result[:caphive_total_units] = caphive_total
      result[:summary_match]      = summary_match
      result[:summary_diff]       = summary_diff.round(8)
      result[:movement]          = movement_reconciliation(ctx, fund: fund, fus: fus, scheme: scheme)

      ctx[:issues] << if summary_match
                        { type: :success, message: "#{isin}: Summary match — #{rta_closing} units", severity: :success }
                      else
                        { type: :blocking,
                          message: "#{isin}: Summary break — RTA #{rta_closing}, CapHive #{caphive_total}, diff #{summary_diff.round(4)}",
                          severity: :blocking }
                      end

      # Folio reconciliation
      rta_folio_numbers = Set.new
      folio_results     = []
      # R1: this scheme's commitments and their investors in two queries, not two per folio. Keyed on the
      # downcased folio id: MySQL compares folio_id case-insensitively, so the per-folio find_by this replaces
      # matched "ab12" to "AB12" and the hash lookup must too. Where two commitments share a folio id the
      # lowest id wins - find_by had no order, so it picked one arbitrarily.
      commitments_by_folio = fund.capital_commitments.where(unit_type: fus.name).where.not(folio_id: nil)
                                 .includes(:investor).order(:id)
                                 .each_with_object({}) { |c, by_folio| by_folio[c.folio_id.downcase] ||= c }

      (scheme[:folios] || []).each do |folio|
        folio_number = folio[:folio_number].to_s.strip
        rta_folio_numbers << folio_number

        # Include unit_type so the same folio_id in two unit classes resolves to the correct commitment
        # (the lookup above is already limited to this scheme's unit_type)
        cc = commitments_by_folio[folio_number.downcase]
        unless cc
          folio_results << { folio_number: folio_number, investor_name: folio[:investor_name],
                             status: :unmatched, message: "Folio #{folio_number} not found in CapHive" }
          ctx[:issues] << { type: :blocking, message: "#{isin}: Folio #{folio_number} not found in CapHive", severity: :blocking }
          next
        end

        rta_units     = folio[:closing_units].to_f
        caphive_units = cc.total_fund_units_quantity.to_f
        diff          = (rta_units - caphive_units).abs
        matched       = within_tolerance?(diff, rta_units, caphive_units)

        caphive_investor_name = cc.investor&.investor_name
        name_mismatch = name_mismatch?(folio[:investor_name], caphive_investor_name)

        continuity = opening_balance_continuity(ctx, isin: isin, folio_number: folio_number, rta_opening_units: folio[:opening_units].to_f)

        folio_results << {
          folio_number: folio_number,
          investor_name: folio[:investor_name],
          caphive_investor_name: caphive_investor_name,
          investor_name_mismatch: name_mismatch,
          holding_type: folio[:holding_type],
          rta_opening_units: folio[:opening_units].to_f,
          rta_closing_units: rta_units,
          caphive_units: caphive_units,
          diff: diff.round(8),
          status: matched ? :match : :break,
          commitment_id: cc.id,
          pending_requests: folio[:pending_requests],
          opening_balance_continuity: continuity
        }

        if name_mismatch
          ctx[:issues] << { type: :warning,
                            message: "#{isin}: Folio #{folio_number} investor name mismatch — RTA \"#{folio[:investor_name]}\" vs CapHive \"#{caphive_investor_name}\"",
                            severity: :warning }
        end

        if continuity && !continuity[:continuous]
          ctx[:issues] << { type: :warning,
                            message: "#{isin}: Folio #{folio_number} opening balance #{continuity[:this_opening_units]} doesn't match prior " \
                                      "statement's closing balance #{continuity[:prior_closing_units]} (diff #{continuity[:diff]})",
                            severity: :warning }
        end

        next if matched

        ctx[:issues] << { type: :blocking,
                          message: "#{isin}: Folio #{folio_number} break — RTA #{rta_units}, CapHive #{caphive_units}, diff #{diff.round(4)}",
                          severity: :blocking }
      end

      # Reverse check — CapHive commitments not in the RTA statement.
      # Zero-balance commitments are excluded: a closed-out folio with nothing
      # left to reconcile shouldn't be flagged as "missing".
      missing_rta = fund.capital_commitments
                        .where(unit_type: fus.name)
                        .where.not(folio_id: [nil, ""])
                        .where.not(folio_id: rta_folio_numbers.to_a)
                        .where.not(total_fund_units_quantity: 0)
                        .includes(:investor)
                        .map do |cc|
                          { folio_id: cc.folio_id, commitment_id: cc.id,
                            investor_name: cc.investor&.investor_name,
                            units: cc.total_fund_units_quantity.to_f.round(8) }
                        end

      missing_rta.each do |m|
        ctx[:issues] << { type: :warning,
                          message: "#{isin}: Folio #{m[:folio_id]} is in CapHive but missing from RTA statement — " \
                                    "#{m[:investor_name]}, #{m[:units]} units",
                          severity: :warning }
      end

      result[:folio_results]      = folio_results
      result[:missing_rta_folios] = missing_rta
      ctx[:scheme_results] << result
    end

    total    = ctx[:scheme_results].size
    breaks   = ctx[:issues].count { |i| i[:severity] == :blocking }
    mark_step_success(report, :reconcile_schemes, message: "#{total} scheme(s) — #{breaks} break(s)") if report
    true
  end

  # Coverage check — every ISIN the fund holds (configured + non-zero balance) vs which
  # ISINs the statement actually included. reconcile_schemes only ever looks at ISINs the
  # PDF mentions, so a scheme the AMC forgot to send is otherwise invisible.
  def check_scheme_coverage(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_scheme_coverage) if report

    unless ctx[:extracted]
      mark_step_skipped(report, :check_scheme_coverage, message: "No extracted data") if report
      return true
    end

    fund = ctx[:fund]
    extracted_isins = (ctx[:extracted][:schemes] || []).filter_map { |s| s[:isin].to_s.strip.presence }.to_set

    coverage = fund.fund_unit_settings.where.not(isin: [nil, ""]).map do |fus|
      commitments    = fund.capital_commitments.where(unit_type: fus.name).where.not(total_fund_units_quantity: 0)
      units_at_stake = commitments.sum(:total_fund_units_quantity).to_f.round(8)
      folio_count    = commitments.count
      covered        = extracted_isins.include?(fus.isin.to_s.strip)

      if !covered && units_at_stake.nonzero?
        ctx[:issues] << { type: :blocking,
                          message: "#{fus.isin} (#{fus.name}): scheme entirely missing from statement — " \
                                    "#{folio_count} folio(s), #{units_at_stake} units at stake",
                          severity: :blocking }
      end

      { isin: fus.isin, unit_type: fus.name, covered: covered, folio_count: folio_count, units_at_stake: units_at_stake }
    end

    ctx[:scheme_coverage] = coverage
    missing = coverage.count { |c| !c[:covered] && c[:units_at_stake].nonzero? }
    mark_step_success(report, :check_scheme_coverage, message: "#{missing} scheme(s) missing from statement") if report
    true
  end

  # Matches "no pending transaction" however the RTA phrases it (None, Nil, NA,
  # N/A, Not Applicable, "-"). RTAs vary their wording, so this can't rely on
  # the LLM normalizing to a single literal value.
  NO_PENDING_REQUEST = /\A(none|nil|na|n\/a|not applicable|nothing|-)\z/i

  # Flags folios where the RTA statement reports a pending transaction.
  def check_pending_requests(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_pending_requests) if report

    unless enabled?("check_pending_requests")
      mark_step_skipped(report, :check_pending_requests, message: "Disabled") if report
      return true
    end

    unless ctx[:extracted]
      mark_step_skipped(report, :check_pending_requests, message: "No extracted data") if report
      return true
    end

    pending_count = 0
    ctx[:scheme_results].each do |scheme_result|
      scheme_result[:pending_request_folios] = []
      (scheme_result[:folio_results] || []).each do |fr|
        next if fr[:pending_requests].blank? || fr[:pending_requests].to_s.strip.match?(NO_PENDING_REQUEST)

        scheme_result[:pending_request_folios] << { folio_number: fr[:folio_number], detail: fr[:pending_requests] }
        ctx[:issues] << { type: :warning,
                          message: "#{scheme_result[:isin]}: Folio #{fr[:folio_number]} has pending request — #{fr[:pending_requests]}",
                          severity: :warning }
        pending_count += 1
      end
    end

    mark_step_success(report, :check_pending_requests, message: "#{pending_count} pending request(s)") if report
    true
  end

  # Emails the reconciliation summary to notify_email when configured.
  def send_reconciliation_report(ctx, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :send_reconciliation_report) if report

    email = support_agent.json_fields["notify_email"].to_s.strip
    unless enabled?("send_report") && email.present?
      mark_step_skipped(report, :send_reconciliation_report, message: "Disabled or no email configured") if report
      return true
    end

    RtaReconciliationMailer.reconciliation_report(support_agent, ctx[:fund], ctx).deliver_now
    Rails.logger.info { "[RtaReconciliationAgent] Report emailed to #{email}" }
    mark_step_success(report, :send_reconciliation_report, message: "Sent to #{email}") if report
    true
  rescue StandardError => e
    Rails.logger.error { "[RtaReconciliationAgent] Email failed: #{e.message}" }
    ctx[:issues] << { type: :warning, message: "Report email failed: #{e.message}", severity: :warning }
    mark_step_failed(report, :send_reconciliation_report, message: "Email error: #{e.message}") if report
    true
  end

  def generate_progress_reports(ctx, support_agent:, **)
    step_report = ctx[:support_agent_report]
    mark_step_running(step_report, :generate_progress_reports) if step_report

    # Health reflects reconciliation outcomes (summary/folio match vs break) only.
    # :warning issues (pending requests, reverse-check informational flags) are
    # excluded from the denominator — they're advisory, not failures, and counting
    # them made a fully-matched run score as low as a run with real breaks.
    active       = ctx[:issues].select { |i| %i[success blocking].include?(i[:severity]) }
    passing      = active.count { |i| i[:severity] == :success }
    health       = active.any? ? (passing.to_f / active.size * 100).round : 100
    has_blocking = ctx[:issues].any? { |i| i[:severity] == :blocking }

    # Always create a new report row so run history accumulates — the
    # step_report (from the controller's find_or_initialize_by) is reused across
    # runs purely to drive the live progress panel, so its json_fields are not a
    # safe place to keep reconciliation results long-term. mark_as_latest! flips
    # this new row to latest and demotes any prior rows for this fund+agent.
    rpt = SupportAgentReport.new(owner: ctx[:target_model], support_agent: support_agent)
    rpt.json_fields = {
      "run_at" => step_report&.json_fields&.dig("run_at") || Time.current.iso8601,
      "statement_date" => ctx[:statement_date_str] || statement_date_from(ctx),
      "amc" => ctx[:extracted]&.dig(:amc),
      "scheme_results" => ctx[:scheme_results],
      "scheme_coverage" => ctx[:scheme_coverage] || [],
      "unit_readiness" => ctx[:unit_readiness] || [],
      "issues" => ctx[:issues],
      "health_score" => health,
      # Run-level audit fields — snapshot what was actually used to judge this run,
      # so a later change to agent settings doesn't retroactively reinterpret old reports.
      "source_document_id" => ctx[:rta_pdf_document_id],
      "llm_model" => @support_agent.llm_model,
      "tolerance_units" => @support_agent.json_fields["tolerance_units"],
      "tolerance_pct" => @support_agent.json_fields["tolerance_pct"],
      "aggregate" => build_aggregate(ctx)
    }
    rpt.status = has_blocking ? SupportAgentReport.statuses[:failed] : SupportAgentReport.statuses[:completed]
    rpt.save!

    mark_step_success(step_report, :generate_progress_reports, message: "Health #{health}%") if step_report
    finalize_report(step_report, status: has_blocking ? "blocked" : "ready") if step_report

    ctx[:support_agent_report] = rpt
    true
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def extract_pdf_text(doc)
    # download gives a real Tempfile; open yields Down::ChunkedIO which PDF::Reader rejects
    doc.file.download { |tempfile| PDF::Reader.new(tempfile).pages.map(&:text).join("\n") }
  rescue StandardError => e
    Rails.logger.error { "[RtaReconciliationAgent] PDF read error: #{e.message}" }
    nil
  end

  def within_tolerance?(abs_diff, rta_val, _caphive_val)
    tol_units = @support_agent.json_fields["tolerance_units"].to_f
    tol_pct   = @support_agent.json_fields["tolerance_pct"].to_f

    return true if abs_diff <= tol_units

    if tol_pct.positive? && rta_val.nonzero?
      pct_diff = abs_diff / rta_val.abs * 100
      return pct_diff <= tol_pct
    end

    false
  end

  def statement_date_from(ctx)
    override = @support_agent.json_fields["statement_date"].to_s.strip
    raw = override.presence || ctx[:extracted]&.dig(:statement_date)
    normalize_statement_date(raw)
  end

  # RTAs format statement dates inconsistently ("31-05-2026", "May 31, 2026",
  # "31/05/2026"...) — normalize to ISO 8601 so the history table sorts and
  # reads consistently across runs for the same fund. Falls back to the raw
  # string if it can't be parsed, rather than dropping the date entirely.
  def normalize_statement_date(raw)
    return nil if raw.blank?

    Date.parse(raw.to_s).iso8601
  rescue Date::Error, TypeError
    raw
  end

  # Same as normalize_statement_date but returns a Date object (or nil) for use
  # in range queries (movement reconciliation), instead of an ISO string for display.
  def normalize_statement_date_obj(raw)
    return nil if raw.blank?

    Date.parse(raw.to_s)
  rescue Date::Error, TypeError
    nil
  end

  # Finds this folio's saved result from the previous run, if one exists.
  def previous_folio_lookup(ctx, isin:, folio_number:)
    prev = ctx[:previous_report]
    return nil unless prev

    scheme_results = prev.json_fields["scheme_results"] || []
    sr = scheme_results.find { |s| s["isin"] == isin }
    return nil unless sr

    (sr["folio_results"] || []).find { |f| f["folio_number"] == folio_number }
  end

  # Compares this period's RTA-reported opening balance against the prior run's
  # RTA-reported closing balance for the same folio. A coincidental match on
  # closing balance alone can mask a real discrepancy that occurred in between —
  # this catches that. Returns nil when there's no prior run to anchor against
  # (e.g. the very first statement for this fund).
  def opening_balance_continuity(ctx, isin:, folio_number:, rta_opening_units:)
    prev_fr = previous_folio_lookup(ctx, isin: isin, folio_number: folio_number)
    return nil unless prev_fr && prev_fr["rta_closing_units"]

    prior_closing = prev_fr["rta_closing_units"].to_f
    diff          = (rta_opening_units - prior_closing).abs

    {
      prior_closing_units: prior_closing,
      this_opening_units: rta_opening_units,
      diff: diff.round(8),
      continuous: within_tolerance?(diff, rta_opening_units, prior_closing)
    }
  end

  # Folio ID matching by coincidence (or a stale/reused folio number) can pair a
  # CapitalCommitment with the wrong investor without showing up as a units
  # mismatch. Case/whitespace-insensitive — RTAs vary capitalization freely.
  def name_mismatch?(rta_name, caphive_name)
    return false if rta_name.blank? || caphive_name.blank?

    normalize_name(rta_name) != normalize_name(caphive_name)
  end

  def normalize_name(name)
    name.to_s.strip.downcase.gsub(/\s+/, " ")
  end

  # Compares RTA-reported subscriptions/redemptions for the period against CapHive's
  # own FundUnit ledger for the same unit_type over the same period. The period runs
  # from the prior run's statement_date to this run's statement_date — without a prior
  # run there's no period to check, so this returns nil (not a failure).
  # Queries FundUnit directly by sign of `quantity` rather than by owner_type, so it
  # also picks up unit transfers (no owner_type) alongside capital calls/distributions.
  def movement_reconciliation(ctx, fund:, fus:, scheme:)
    period_end = ctx[:statement_date]
    period_start = normalize_statement_date_obj(ctx[:previous_report]&.json_fields&.dig("statement_date"))
    return nil unless period_start && period_end && period_start < period_end

    units = FundUnit.where(fund: fund, unit_type: fus.name, issue_date: period_start..period_end)
    caphive_subscribed = units.where("quantity > 0").sum(:quantity).to_f
    caphive_redeemed    = units.where("quantity < 0").sum(:quantity).to_f.abs

    rta_subscribed = scheme.dig(:summary, :subscriptions_units).to_f
    rta_redeemed   = scheme.dig(:summary, :redemptions_units).to_f

    sub_diff = (rta_subscribed - caphive_subscribed).abs
    red_diff = (rta_redeemed - caphive_redeemed).abs

    {
      period_start: period_start.iso8601,
      period_end: period_end.iso8601,
      rta_subscribed_units: rta_subscribed,
      caphive_subscribed_units: caphive_subscribed.round(8),
      subscribed_diff: sub_diff.round(8),
      rta_redeemed_units: rta_redeemed,
      caphive_redeemed_units: caphive_redeemed.round(8),
      redeemed_diff: red_diff.round(8),
      matched: within_tolerance?(sub_diff, rta_subscribed, caphive_subscribed) &&
               within_tolerance?(red_diff, rta_redeemed, caphive_redeemed)
    }
  end

  # Fund-wide rollup across every reconciled scheme, so the report can answer
  # "how much of this fund actually reconciled" at a glance instead of only
  # per-line detail.
  # Three tiers, each a subset of the one before:
  #   Tier A (fund-wide)    — every unit type with live commitments, regardless of config
  #   Tier B (ISIN-eligible) — the subset of Tier A that has an ISIN configured at all
  #   Tier C (this statement) — the subset of Tier B that this specific upload covered
  # The A→B gap is a configuration problem (check_unit_reconciliation_readiness).
  # The B→C gap is a this-statement problem (check_scheme_coverage).
  def build_aggregate(ctx)
    schemes   = ctx[:scheme_results] || []
    folios    = schemes.flat_map { |s| s[:folio_results] || [] }
    coverage  = ctx[:scheme_coverage] || []
    readiness = ctx[:unit_readiness] || []

    broken_folios = folios.select { |f| f[:status] == :break }
    isin_eligible = readiness.select { |r| r[:isin_configured] }

    {
      # Tier A — fund-wide, independent of configuration or statement
      fund_unit_types_total: readiness.size,
      fund_wide_folio_count: readiness.sum { |r| r[:folio_count] },
      fund_wide_units: readiness.sum { |r| r[:units] }.round(8),
      # Tier B — ISIN-eligible (subset of A)
      fund_unit_types_missing_isin: readiness.size - isin_eligible.size,
      isin_eligible_folio_count: isin_eligible.sum { |r| r[:folio_count] },
      isin_eligible_units: isin_eligible.sum { |r| r[:units] }.round(8),
      # Tier C — what this statement actually covered (subset of B)
      schemes_configured: coverage.size,
      schemes_covered: coverage.count { |c| c[:covered] },
      schemes_missing_from_statement: coverage.count { |c| !c[:covered] && c[:units_at_stake].nonzero? },
      folios_in_statement: folios.size,
      folios_matched: folios.count { |f| f[:status] == :match },
      folios_broken: broken_folios.size,
      folios_unmatched_in_caphive: folios.count { |f| f[:status] == :unmatched },
      folios_missing_from_statement: schemes.sum { |s| (s[:missing_rta_folios] || []).size },
      rta_total_units: schemes.sum { |s| s.dig(:extracted_summary, :closing_units).to_f }.round(8),
      caphive_total_units: schemes.sum { |s| s[:caphive_total_units].to_f }.round(8),
      net_unit_diff: schemes.sum { |s| s.dig(:extracted_summary, :closing_units).to_f - s[:caphive_total_units].to_f }.round(8),
      break_units_total: broken_folios.sum { |f| f[:diff].to_f }.round(8)
    }
  end

  def extraction_prompt(pdf_text)
    <<~PROMPT
      You are a fund operations assistant processing an RTA (Registrar and Transfer Agent) unit statement.
      These statements vary in format across RTAs — column names, ordering, and layout differ.
      Your job is to semantically identify and extract the data regardless of how it is presented.

      Rules:
      - A statement may cover one or more ISINs (unit classes / schemes). Produce one entry per ISIN.
      - Column headings may vary: "Units", "No of Units", "Quantity" all mean the same thing.
      - Numbers may use Indian lakh formatting (e.g. 2,78,465.00) — treat these as plain decimals.
      - "Pending Requests" may be labelled "Pending TXN", "Outstanding Requests", etc. If there is no
        pending transaction for a folio (e.g. it says "None", "Nil", "NA", "-", or the column is blank),
        return null for that folio — do not return the literal word.
      - "Holding Type" may be labelled "Investor Type", "Residency", etc.
      - "amc" is the name of the Asset Management Company / fund manager — not the RTA/registrar
        printing the statement (e.g. CAMS, KFintech) and not the fund's own name. If the AMC is not
        explicitly labelled in the statement, return null rather than guessing.
      - If a field is not present in the statement, use null.
      - Return ONLY a valid JSON object. No prose, no markdown fences outside the JSON.

      Output schema:
      {
        "amc":            "string",
        "statement_date": "string",
        "schemes": [
          {
            "scheme":  "string",
            "isin":    "string",
            "nav":     0.0,
            "summary": {
              "opening_units":       0.0,
              "subscriptions_units": 0.0,
              "redemptions_units":   0.0,
              "closing_units":       0.0
            },
            "folios": [
              {
                "folio_number":     "string",
                "investor_name":    "string",
                "holding_type":     "string",
                "opening_units":    0.0,
                "closing_units":    0.0,
                "pending_requests": "string"
              }
            ]
          }
        ]
      }

      === RTA STATEMENT ===
      #{pdf_text}
    PROMPT
  end
end
