# frozen_string_literal: true

# DealManagementAgent monitors a single open deal end-to-end:
#   1. Stagnation + overdue activity detection     (check_progress)
#   2. Required document checklist                 (check_documents)
#   3. LLM term extraction from deal data room     (extract_terms)
#   4. Per-investor note summary + scoring         (summarize_notes / score_investors)
#   5. Pipeline digest email (all issues in one)   (notify_email)
#
# Each capability is independently toggled via json_fields on the SupportAgent record.
# The agent targets ONE deal at a time (on-demand or scheduled).
#
# Migrations required before use:
#   • deal_investors: ai_score (integer nullable), ai_grade (varchar 10 nullable)
class DealManagementAgent < SupportAgentService
  DESCRIPTION = "Monitors deal health, sends reminders, checks documents, extracts terms, scores investors, and generates weekly summaries — scoped to one deal."

  LONG_DESCRIPTION = <<~DESC
    Runs eleven independently-toggleable capabilities against a single open deal:

    • Check Deal Progress  — flags stagnant investors (no update/activity within stagnant_days)
                             and surfaces overdue DealActivity steps.
    • Check Document Checklist — verifies required_docs are present in the deal data room
                             (case-insensitive match on document name).
    • Extract Deal Terms  — sends all deal data-room documents to the LLM and stores the
                             extracted JSON in the deal-level report. Cached: re-runs only when
                             documents or the extraction prompt change.
    • Investor Pipeline   — for each active (non-Declined, non-Complete) DealInvestor:
                               • Collects documents (investor folder + completed activity attachments)
                               • Optionally summarises with LLM (summarize_notes)
                               • Optionally scores with LLM via uploaded skill file (score_investors)
                               • Writes ai_score / ai_grade back to DealInvestor
                               • Saves a per-investor SupportAgentReport (overwritten on re-run)
    • Period Deltas       — computes new investors, step transitions, and status changes
                             within the configured report_period window (default 7 days).
    • Stagnation Breakdown — three-way stagnation analysis: newly stagnant, still stagnant,
                             and recovered investors compared against the previous report.
    • Tasks Summary       — aggregates overdue, upcoming (7-day window), pending (no due date
                             or beyond 7 days), and completed tasks for the deal and its investors.
    • Charts Data         — pre-computes funnel, source mix, and lead mix chart data
                             from the deal's current pipeline state.
    • AI Insight          — optional single LLM call generating an actionable one-liner
                             based on the week's data (toggled by enable_ai_insight).
    • Send Email Digest   — sends a pipeline summary to notify_email after every run,
                             covering all overdue activities, document gaps, and investor scores.
                             Optionally sends a lightweight weekly summary email.
                             A blocker alert is appended when any :blocking issue exists.

    Closed deals are not processed. All notifications go to notify_email.
    Weekly summary features are toggled by the weekly_summary config key.
  DESC

  REQUIRED_SCORE_KEYS  = %w[overall_score grade summary dimensions].freeze
  SUPPORTED_EXTENSIONS = %w[.pdf .txt .md .xlsx .xls .pptx .ppt .docx .doc .csv].freeze
  CHARS_PER_DOC        = 5_000   # per-document text cap before truncation
  CHARS_TOTAL          = 50_000  # per-investor total cap; oldest docs truncated first

  # Built-in scoring rubric used when no scoring_skill_file is uploaded.
  # Upload a custom scoring_skill_file document to override this with a deal-specific rubric.
  DEFAULT_SCORING_RUBRIC = <<~RUBRIC
    You are an expert deal analyst evaluating an investor's likelihood to commit to this deal.
    Score the investor across these four dimensions (weights must sum to 1.0):

    1. Engagement & Responsiveness (weight 0.30)
       How actively is the investor participating? Are activities completed on time?
       Are there overdue steps, stagnant periods, or prompt responses?

    2. Document Readiness (weight 0.25)
       Have they submitted required documents (term sheets, KYC, agreements)?
       Are activity attachments present and recent?

    3. Commitment Signals (weight 0.25)
       Do notes and documents signal intent to invest?
       Is a specific amount discussed? Is the investor asking detailed diligence questions?

    4. Pipeline Health (weight 0.20)
       Where is the investor in the pipeline? Are they progressing through stages?
       Are there any blockers or red flags in their activity history?

    Scoring guidelines:
    - 90–100: Exceptional — clear commitment, all docs ready, fast responses
    - 80–89 : Strong — actively engaged, minor gaps only
    - 70–79 : Good — on track, some follow-ups needed
    - 60–69 : Adequate — engaged but slow or missing items
    - 50–59 : Mixed — inconsistent engagement or significant gaps
    - 40–49 : Underperforming — stalled, missing key documents or responses
    - 0–39  : Distressed — no activity, unlikely to commit without intervention
  RUBRIC

  STEP_LABELS = {
    initialize_agent: "Initialize",
    check_deal_progress: "Deal Progress",
    check_document_checklist: "Doc Checklist",
    extract_deal_terms: "Extract Terms",
    run_investor_pipeline: "Investor Pipeline",
    calculate_period_deltas: "Period Deltas",
    calculate_stagnation_breakdown: "Stagnation Breakdown",
    aggregate_deal_tasks: "Tasks Summary",
    compute_charts_data: "Charts Data",
    generate_weekly_insight: "AI Insight",
    send_email_digest: "Email Digest",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :check_deal_progress
  step :check_document_checklist
  step :extract_deal_terms
  step :run_investor_pipeline
  step :calculate_period_deltas
  step :calculate_stagnation_breakdown
  step :aggregate_deal_tasks
  step :compute_charts_data
  step :generate_weekly_insight
  step :send_email_digest
  step :generate_progress_reports

  # Returns the target deal(s) for this agent run.
  # When called with a Deal instance, returns it directly.
  # When called with an entity ID, returns deals scoped by the deal_ids
  # config if set, otherwise all non-closed deals for that entity.
  # When called with a deal ID, returns that single deal.
  #
  # @param entity_or_deal_id [Integer, Deal] an entity ID, deal ID, or Deal instance
  # @return [Array<Deal>, ActiveRecord::Relation]
  def targets(entity_or_deal_id)
    if entity_or_deal_id.is_a?(Deal)
      [entity_or_deal_id]
    elsif Entity.exists?(entity_or_deal_id)
      scope = Deal.where(entity_id: entity_or_deal_id).where.not(status: "Closed")
      configured_ids = SupportAgent.find_by(entity_id: entity_or_deal_id, agent_type: "DealManagementAgent")
                                   &.json_fields&.dig("deal_ids").to_s.split(",").map(&:strip).compact_blank.map(&:to_i)
      configured_ids.present? ? scope.where(id: configured_ids) : scope
    else
      deal = Deal.find(entity_or_deal_id)
      [deal]
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error { "[DealManagementAgent] Target not found: #{e.message}" }
    []
  end

  # Human descriptions of the steps each json_fields toggle gates.
  CHECK_TOGGLES = {
    "check_progress" => "the deal progress / stagnation check",
    "check_documents" => "the document checklist check",
    "extract_terms" => "term extraction from deal documents",
    "summarize_notes" => "investor note summaries",
    "score_investors" => "investor scoring",
    "weekly_summary" => "the weekly summary email and charts",
    "enable_ai_insight" => "the AI insight section of the weekly summary"
  }.freeze

  # Setup health check — unset toggles silently skip steps, and a blank
  # notify_email means the digest (this agent's main output) never sends
  # while the report still finishes green.
  def self.config_issues(support_agent)
    issues = missing_toggle_issues(support_agent, CHECK_TOGGLES)

    issues << "'notify_email' is blank — the deal digest email (this agent's main output) will never be sent." if (support_agent.json_fields || {})["notify_email"].to_s.strip.blank?

    # Optional custom scoring rubric: field exists but no file uploaded means the
    # built-in default rubric is silently used, which users often don't realize.
    fcf = support_agent.form_custom_fields.find { |f| f.name == "scoring_skill_file" && f.field_type == "File" }
    issues << "No file uploaded for '#{fcf.human_label}' — investor scoring will use the built-in default rubric." if fcf && !support_agent.documents.exists?(name: fcf.human_label)

    issues
  end

  private

  # ── Step 1 ── Load agent + LLM, validate deal, initialise issues hash.
  # Returns false to halt pipeline when deal is Closed or agent is disabled.
  def initialize_agent(ctx, target: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :initialize_agent) if report

    super # loads @support_agent, ctx[:support_agent], ctx[:llm]

    deal       = target
    ctx[:deal] = deal

    ctx[:issues] = {
      progress_issues: [],
      document_issues: [],
      digest_issues: []
    }

    Rails.logger.info { "[DealManagementAgent] Initializing for Deal ID=#{deal.id} '#{deal.name}'" }

    unless deal.is_a?(Deal)
      Rails.logger.error { "[DealManagementAgent] Target is not a Deal (#{deal.class})" }
      alert_user(ctx, "Deal Management Agent: invalid target — aborting", :danger)
      mark_step_failed(report, :initialize_agent, message: "Invalid target — #{deal.class}") if report
      return false
    end

    if deal.status != "Open"
      mark_step_skipped(report, :initialize_agent, message: "Deal is #{deal.status}") if report
      alert_user(ctx, "Deal Management Agent: '#{deal.name}' is #{deal.status} — skipping", :warning)
      return false
    end

    alert_user(ctx, "Deal Management Agent started for '#{deal.name}'", :info)
    mark_step_success(report, :initialize_agent, message: "Initialized for '#{deal.name}'") if report
    @support_agent.enabled?
  end

  # ── Step 2 ── Stagnation and overdue activity detection across all active investors.
  # Toggled by check_progress (Yes/No). Always returns true so pipeline continues.
  def check_deal_progress(ctx, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_deal_progress) if report

    alert_user(ctx, "Deal Progress: checking stagnation and overdue activities…", :info)
    unless enabled?("check_progress")
      ctx[:issues][:progress_issues] << { type: :info, message: "Progress check disabled", severity: :success }
      mark_step_skipped(report, :check_deal_progress, message: "Disabled") if report
      alert_user(ctx, "Deal Progress: disabled — skipped", :info)
      return true
    end

    stagnant_days = @support_agent.json_fields["stagnant_days"].to_i.nonzero? || 14

    investors     = active_deal_investors(deal)

    health_scores = {}

    investors.each do |di|
      # Stagnation: investor record AND all its activities must both be stale
      investor_updated_recently = di.updated_at >= stagnant_days.days.ago
      activities_updated_recently = di.deal_activities.any? { |a| a.updated_at >= stagnant_days.days.ago }

      if !investor_updated_recently && !activities_updated_recently
        ctx[:issues][:progress_issues] << {
          type: :stagnant,
          severity: :blocking,
          message: "#{di.investor_name} has had no activity for more than #{stagnant_days} days",
          investor_id: di.id,
          investor_name: di.investor_name
        }
      end

      # Overdue activities for this investor
      di.deal_activities
        .select { |a| a.status != "Complete" && a.status != "complete" && a.by_date.present? && a.by_date < Time.zone.today }
        .each do |act|
        ctx[:issues][:progress_issues] << {
          type: :overdue,
          severity: :blocking,
          message: "#{di.investor_name}: '#{act.title}' was due #{act.by_date.strftime('%d %b %Y')}",
          investor_id: di.id,
          investor_name: di.investor_name,
          activity_id: act.id,
          activity_title: act.title,
          by_date: act.by_date.iso8601
        }
      end

      health_scores[di.investor_name] = di.health_score
    end

    ctx[:health_scores] = health_scores

    if ctx[:issues][:progress_issues].empty?
      ctx[:issues][:progress_issues] << {
        type: :info,
        severity: :success,
        message: "No stagnant investors or overdue activities"
      }
    end

    stagnant = ctx[:issues][:progress_issues].count { |i| i[:type] == :stagnant }
    overdue  = ctx[:issues][:progress_issues].count { |i| i[:type] == :overdue }
    Rails.logger.info { "[DealManagementAgent] Progress: #{stagnant} stagnant, #{overdue} overdue activities" }
    if stagnant.zero? && overdue.zero?
      mark_step_success(report, :check_deal_progress, message: "All investors on track") if report
      alert_user(ctx, "Deal Progress: all investors on track ✓", :success)
    else
      parts = []
      parts << "#{stagnant} stagnant investor#{'s' if stagnant != 1}" if stagnant.positive?
      parts << "#{overdue} overdue activit#{'ies' if overdue != 1}#{'y' if overdue == 1}" if overdue.positive?
      mark_step_success(report, :check_deal_progress, message: "#{parts.join(', ')} found") if report
      alert_user(ctx, "Deal Progress: #{parts.join(', ')} found", :warning)
    end
    true
  end

  # ── Step 3 ── Verify required documents exist in the deal data room.
  # Toggled by check_documents (Yes/No). Case-insensitive name matching.
  def check_document_checklist(ctx, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_document_checklist) if report

    alert_user(ctx, "Document Checklist: verifying required documents…", :info)
    unless enabled?("check_documents")
      ctx[:issues][:document_issues] << { type: :info, severity: :success, message: "Document checklist disabled" }
      mark_step_skipped(report, :check_document_checklist, message: "Disabled") if report
      alert_user(ctx, "Document Checklist: disabled — skipped", :info)
      return true
    end

    required = @support_agent.json_fields["required_docs"].to_s
                             .split(",").map(&:strip).compact_blank

    if required.empty?
      ctx[:issues][:document_issues] << {
        type: :info,
        severity: :success,
        message: "No required documents configured — checklist skipped"
      }
      mark_step_skipped(report, :check_document_checklist, message: "No docs configured") if report
      return true
    end

    uploaded = deal.deal_documents_folder.documents.pluck(:name).map(&:downcase)

    required.each do |name|
      ctx[:issues][:document_issues] << if uploaded.include?(name.downcase)
                                          {
                                            type: :present,
                                            severity: :success,
                                            message: "#{name} is present in the data room",
                                            document_name: name
                                          }
                                        else
                                          {
                                            type: :missing,
                                            severity: :blocking,
                                            message: "#{name} is missing from the data room",
                                            document_name: name
                                          }
                                        end
    end

    missing = ctx[:issues][:document_issues].count { |i| i[:severity] == :blocking }
    Rails.logger.info { "[DealManagementAgent] Checklist: #{required.size} required, #{missing} missing" }
    if missing.zero?
      mark_step_success(report, :check_document_checklist, message: "All #{required.size} docs present") if report
      alert_user(ctx, "Document Checklist: all #{required.size} required documents present ✓", :success)
    else
      mark_step_success(report, :check_document_checklist, message: "#{missing} of #{required.size} missing") if report
      alert_user(ctx, "Document Checklist: #{missing} of #{required.size} documents missing", :warning)
    end
    true
  end

  # ── Step 4 ── LLM term extraction from all deal data-room documents.
  # Runs once per deal; cached when documents and prompt are both unchanged.
  # Toggled by extract_terms (Yes/No). Always returns true (soft-fail).
  def extract_deal_terms(ctx, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :extract_deal_terms) if report

    alert_user(ctx, "Extract Terms: reading deal data room…", :info)
    unless enabled?("extract_terms")
      ctx[:extracted_terms] = nil
      mark_step_skipped(report, :extract_deal_terms, message: "Disabled") if report
      alert_user(ctx, "Extract Terms: disabled — skipped", :info)
      return true
    end

    docs = deal.deal_documents_folder.documents.to_a
    if docs.empty?
      Rails.logger.info { "[DealManagementAgent] No documents in deal data room — skipping term extraction" }
      mark_step_skipped(report, :extract_deal_terms, message: "No documents in data room") if report
      alert_user(ctx, "Extract Terms: no documents in data room — skipped", :warning)
      return true
    end

    current_fingerprint = compute_doc_fingerprint(docs)
    current_prompt      = @support_agent.json_fields["term_extraction_prompt"].to_s.strip

    # Check cache on the latest previous report (if any) — new records are created each run
    existing_report = SupportAgentReport
                      .where(owner: deal, support_agent: @support_agent)
                      .latest_only
                      .first
    if existing_report
      jf = existing_report.json_fields || {}
      if jf["term_extraction_fingerprint"] == current_fingerprint &&
         jf["term_extraction_prompt_used"] == current_prompt &&
         jf["extracted_terms"].present?
        Rails.logger.info { "[DealManagementAgent] Term extraction cache HIT — carrying forward" }
        mark_step_success(report, :extract_deal_terms, message: "Cached (#{jf['extracted_terms'].count { |_, v| v.present? }} terms)") if report
        alert_user(ctx, "Extract Terms: using cached results (documents unchanged) ✓", :success)
        ctx[:extracted_terms]             = jf["extracted_terms"]
        ctx[:term_extraction_fingerprint] = current_fingerprint
        ctx[:term_extraction_prompt_used] = current_prompt
        return true
      end
    end

    # Cache miss — run LLM
    alert_user(ctx, "Extract Terms: calling LLM on #{docs.size} document(s)…", :info)
    Rails.logger.info { "[DealManagementAgent] Term extraction cache MISS — calling LLM" }
    doc_text = format_documents_for_prompt(docs)

    if doc_text.blank?
      Rails.logger.warn { "[DealManagementAgent] Could not extract text from any deal documents" }
      return true
    end

    prompt   = build_term_extraction_prompt(current_prompt, doc_text)
    response = ctx[:llm].ask(prompt)
    raw      = extract_text_content(response)

    match = raw.match(/```json\s*(\{.+?\})\s*```/m) ||
            raw.match(/```\s*(\{.+?\})\s*```/m) ||
            raw.match(/(\{.+\})/m)

    if match
      ctx[:extracted_terms]             = JSON.parse(match[1])
      ctx[:term_extraction_fingerprint] = current_fingerprint
      ctx[:term_extraction_prompt_used] = current_prompt
      filled = ctx[:extracted_terms].count { |_, v| v.present? }
      Rails.logger.info { "[DealManagementAgent] Terms extracted: #{ctx[:extracted_terms].keys.join(', ')}" }
      mark_step_success(report, :extract_deal_terms, message: "#{filled} term(s) extracted") if report
      alert_user(ctx, "Extract Terms: #{filled} term(s) extracted ✓", :success)
    else
      Rails.logger.warn { "[DealManagementAgent] LLM returned no parseable JSON for term extraction" }
      mark_step_success(report, :extract_deal_terms, message: "No parseable JSON returned") if report
      alert_user(ctx, "Extract Terms: LLM returned no parseable terms", :warning)
    end
    true
  rescue StandardError => e
    Rails.logger.error { "[DealManagementAgent] Term extraction failed: #{e.message}" }
    ctx[:term_extraction_error] = e.message
    mark_step_failed(report, :extract_deal_terms, message: e.message) if report
    alert_user(ctx, "Extract Terms: failed — #{e.message}", :danger)
    true # soft-fail
  end

  # ── Step 5 ── Per-investor loop: collect docs, summarise, score, save report.
  # Always runs regardless of toggle state (inner LLM calls are individually toggled).
  def run_investor_pipeline(ctx, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :run_investor_pipeline) if report

    investors         = active_deal_investors(deal)
    score_leaderboard = []
    period_start, period_end, period_label = resolve_period

    Rails.logger.info { "[DealManagementAgent] Investor pipeline: #{investors.size} active investor(s)" }
    alert_user(ctx, "Investor Pipeline: processing #{investors.size} active investor(s)…", :info)

    investors.each do |di|
      alert_user(ctx, "Investor Pipeline: analysing #{di.investor_name}…", :info)
      process_single_investor(ctx, di, period_start, period_end, period_label, score_leaderboard)
      alert_user(ctx, "Investor Pipeline: #{di.investor_name} done ✓", :success)
    rescue StandardError => e
      Rails.logger.error { "[DealManagementAgent] Pipeline error for DealInvestor##{di.id}: #{e.message}" }
      alert_user(ctx, "Investor Pipeline: #{di.investor_name} failed — #{e.message}", :danger)
      save_investor_report(di, nil, "failed", period_label, error: e.message)
    end

    ctx[:score_leaderboard] = score_leaderboard.sort_by { |r| -(r[:ai_score] || 0) }
    scored_count = score_leaderboard.count { |r| r[:ai_score].present? }
    mark_step_success(report, :run_investor_pipeline, message: "#{investors.size} investor(s), #{scored_count} scored") if report
    alert_user(ctx, "Investor Pipeline: all investors processed ✓", :success)
    true
  end

  # ── Step 6 ── Computes what changed during the reporting period: new investors,
  # step transitions (via audit trail), and status changes.
  # Toggled by weekly_summary (Yes/No). Always returns true.
  #
  # @param ctx [Hash] pipeline context
  # @param deal [Deal] the target deal
  # @return [Boolean] always true
  def calculate_period_deltas(ctx, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :calculate_period_deltas) if report

    unless enabled?("weekly_summary")
      mark_step_skipped(report, :calculate_period_deltas, message: "Weekly summary disabled") if report
      return true
    end

    @report_period = [@support_agent.json_fields["report_period"].to_i, 1].max
    @period_start  = @report_period.days.ago.beginning_of_day
    @period_end    = Time.current
    ctx[:period_start] = @period_start
    ctx[:period_end]   = @period_end

    di_ids = deal.deal_investor_ids
    ctx[:deal_investor_ids] = di_ids

    period_audits = if di_ids.present?
                      Audited::Audit
                        .where(auditable_type: "DealInvestor", auditable_id: di_ids, action: "update")
                        .where(created_at: @period_start..@period_end)
                        .where("audited_changes LIKE ? OR audited_changes LIKE ?",
                               "%deal_activity_id%", "%status%")
                        .to_a
                    else
                      []
                    end

    ctx[:period_deltas] = {
      period_start: @period_start.iso8601,
      period_end: @period_end.iso8601,
      report_period: @report_period,
      new_investors: count_new_investors(deal),
      step_transitions: compute_step_transitions(deal, di_ids, period_audits),
      status_changes: compute_status_changes(deal, di_ids, period_audits)
    }

    total_new = ctx[:period_deltas][:new_investors][:count]
    total_transitions = ctx[:period_deltas][:step_transitions][:total]
    total_status = ctx[:period_deltas][:status_changes][:total]

    if report
      mark_step_success(report, :calculate_period_deltas,
                        message: "#{total_new} new, #{total_transitions} transitions, #{total_status} status changes")
    end
    alert_user(ctx, "Period Deltas: #{total_new} new investors, #{total_transitions} transitions, #{total_status} status changes", :info)
    true
  end

  # ── Step 7 ── Three-way stagnation breakdown comparing current state vs previous report.
  # Categorises investors as newly stagnant, still stagnant, or now active (recovered).
  # Toggled by weekly_summary (Yes/No). Always returns true.
  #
  # @param ctx [Hash] pipeline context
  # @param deal [Deal] the target deal
  # @return [Boolean] always true
  def calculate_stagnation_breakdown(ctx, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :calculate_stagnation_breakdown) if report

    unless enabled?("weekly_summary")
      mark_step_skipped(report, :calculate_stagnation_breakdown, message: "Disabled") if report
      return true
    end

    investors = active_deal_investors(deal).includes(:deal_activity, :deal_activities)

    global_stagnant_days = @support_agent.json_fields["stagnant_days"].to_i.nonzero? || 14

    current_stagnant_ids = investors.select do |di|
      threshold = di.deal_activity&.days.presence || global_stagnant_days
      investor_stale = di.updated_at < threshold.days.ago
      activities_stale = di.deal_activities.none? { |a| a.updated_at >= threshold.days.ago }
      investor_stale && activities_stale
    end.to_set(&:id)

    previous_report = SupportAgentReport
                      .where(owner: deal, support_agent: @support_agent)
                      .where(status: :completed)
                      .where.not(id: report&.id)
                      .order(created_at: :desc)
                      .first

    previous_stagnant_ids = (
      previous_report&.json_fields&.dig("stagnation_breakdown", "current_stagnant_ids") || []
    ).to_set(&:to_i)

    still_stagnant = current_stagnant_ids & previous_stagnant_ids
    newly_stagnant = current_stagnant_ids - previous_stagnant_ids
    now_active     = previous_stagnant_ids - current_stagnant_ids

    step_map = investors.to_h { |di| [di.id, di.deal_activity&.title] }

    step_days_map = investors.to_h { |di| [di.id, di.deal_activity&.days] }

    all_relevant_ids = (still_stagnant + newly_stagnant + now_active).to_a
    name_map = DealInvestor.where(id: all_relevant_ids).pluck(:id, :investor_name).to_h

    last_activity_map = investors.each_with_object({}) do |di, map|
      latest_activity = di.deal_activities.map(&:updated_at).max
      map[di.id] = [di.updated_at, latest_activity].compact.max.iso8601
    end

    ctx[:stagnation_breakdown] = {
      total: current_stagnant_ids.size,
      still_stagnant: still_stagnant.map { |id| { id: id, name: name_map[id], last_activity: last_activity_map[id], step_name: step_map[id], step_days: step_days_map[id] } },
      newly_stagnant: newly_stagnant.map { |id| { id: id, name: name_map[id], last_activity: last_activity_map[id], step_name: step_map[id], step_days: step_days_map[id] } },
      now_active: now_active.map { |id| { id: id, name: name_map[id], step_name: step_map[id] } },
      still_stagnant_count: still_stagnant.size,
      newly_stagnant_count: newly_stagnant.size,
      now_active_count: now_active.size,
      current_stagnant_ids: current_stagnant_ids.to_a,
      stagnant_days: global_stagnant_days
    }

    if report
      mark_step_success(report, :calculate_stagnation_breakdown,
                        message: "#{newly_stagnant.size} new, #{still_stagnant.size} still, #{now_active.size} recovered")
    end
    alert_user(ctx, "Stagnation: #{newly_stagnant.size} new, #{still_stagnant.size} still, #{now_active.size} recovered", :info)
    true
  end

  # ── Step 8 ── Aggregates tasks for the deal and its investors into overdue,
  # upcoming (due within 7 days), pending (no due date or due beyond 7 days),
  # and completed buckets. Highlights the most overdue task and
  # lists tasks due soon (capped by max_tasks_in_email config).
  # Toggled by weekly_summary (Yes/No). Always returns true.
  #
  # @param ctx [Hash] pipeline context
  # @param deal [Deal] the target deal
  # @return [Boolean] always true
  def aggregate_deal_tasks(ctx, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :aggregate_deal_tasks) if report

    unless enabled?("weekly_summary")
      mark_step_skipped(report, :aggregate_deal_tasks, message: "Disabled") if report
      return true
    end

    di_ids = ctx[:deal_investor_ids] || deal.deal_investor_ids

    all_tasks = Task.where(
      "(owner_type = 'Deal' AND owner_id = ?) OR
     (owner_type = 'DealInvestor' AND owner_id IN (?))",
      deal.id, di_ids
    ).includes(:assigned_to, :rich_text_details).to_a

    period_start = ctx[:period_start] || @period_start

    # Pending = all non-overdue incomplete tasks (superset of upcoming).
    # Upcoming = subset of pending due within 7 days, shown separately for urgency.
    upcoming_horizon = Time.zone.today + 7.days
    overdue   = all_tasks.select { |t| !t.completed && t.due_date.present? && t.due_date < Time.zone.today }
    pending   = all_tasks.select { |t| !t.completed && (t.due_date.blank? || t.due_date >= Time.zone.today) }
    upcoming  = pending.select { |t| t.due_date.present? && t.due_date <= upcoming_horizon }
    completed = all_tasks.select { |t| t.completed && t.updated_at >= period_start }

    max_tasks = [@support_agent.json_fields["max_tasks_in_email"].to_i, 5].max
    highlighted_overdue = overdue.min_by(&:due_date)
    pending_due_soon = upcoming.sort_by(&:due_date).first(max_tasks)

    ctx[:tasks_summary] = {
      overdue_count: overdue.size,
      upcoming_count: upcoming.size,
      pending_count: pending.size,
      completed_count: completed.size,
      highlighted_overdue: format_deal_task(highlighted_overdue),
      overdue_tasks: overdue.sort_by(&:due_date).first(max_tasks).map { |t| format_deal_task(t) },
      pending_due_soon: pending_due_soon.map { |t| format_deal_task(t) },
      pending_tasks: pending.sort_by { |t| t.due_date || Date.new(9999) }.first(max_tasks).map { |t| format_deal_task(t) },
      completed_tasks: completed.sort_by(&:updated_at).reverse.first(max_tasks).map { |t| format_deal_task(t) },
      all_overdue_ids: overdue.map(&:id),
      all_upcoming_ids: upcoming.map(&:id),
      all_pending_ids: pending.map(&:id),
      all_completed_ids: completed.map(&:id)
    }

    if report
      mark_step_success(report, :aggregate_deal_tasks,
                        message: "#{overdue.size} overdue, #{upcoming.size} upcoming, #{pending.size} pending, #{completed.size} completed")
    end
    alert_user(ctx, "Tasks: #{overdue.size} overdue, #{upcoming.size} upcoming, #{pending.size} pending, #{completed.size} completed", :info)
    true
  end

  # ── Step 9 ── Pre-computes chart data from the deal's current pipeline state.
  # Supports three chart types: funnel (investors per step), source mix, and lead mix.
  # Filtered by preset_charts config. Toggled by weekly_summary (Yes/No).
  #
  # @param ctx [Hash] pipeline context
  # @param deal [Deal] the target deal
  # @return [Boolean] always true
  def compute_charts_data(ctx, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :compute_charts_data) if report

    unless enabled?("weekly_summary")
      mark_step_skipped(report, :compute_charts_data, message: "Disabled") if report
      return true
    end

    preset_charts = @support_agent.json_fields["preset_charts"].to_s
                                  .split(",").map(&:strip).compact_blank
    preset_charts = %w[funnel source lead] if preset_charts.empty?

    investors = deal.deal_investors.includes(:deal_activity, :deal_activities)

    charts = {}

    if preset_charts.include?("funnel")
      templates = DealActivity.where(deal_id: deal.id, deal_investor_id: nil).order(:sequence)
      charts[:funnel] = templates.map do |tmpl|
        count = investors.count { |di| di.deal_activity_id == tmpl.id }
        { step_title: tmpl.title, investor_count: count, sequence: tmpl.sequence }
      end
    end

    if preset_charts.include?("source")
      source_groups = investors.group_by(&:source)
      charts[:source_mix] = source_groups.map do |source, dis|
        { label: source.presence || "Unknown", value: dis.sum(&:total_amount_cents).to_i }
      end.sort_by { |d| -d[:value] }
    end

    if preset_charts.include?("lead")
      lead_groups = investors.group_by(&:deal_lead)
      charts[:lead_mix] = lead_groups.map do |lead, dis|
        { label: lead.presence || "Unknown", value: dis.sum(&:total_amount_cents).to_i }
      end.sort_by { |d| -d[:value] }
    end

    ctx[:charts_data] = charts

    if report
      mark_step_success(report, :compute_charts_data,
                        message: "#{charts.keys.join(', ')} computed")
    end
    alert_user(ctx, "Charts: #{charts.keys.join(', ')} computed", :info)
    true
  rescue StandardError => e
    Rails.logger.error { "[DealManagementAgent] Charts computation failed: #{e.message}" }
    ctx[:charts_data] = {}
    mark_step_failed(report, :compute_charts_data, message: e.message) if report
    alert_user(ctx, "Charts: failed — #{e.message}", :warning)
    true
  end

  # ── Step 10 ── Optional LLM call to generate an actionable one-liner insight.
  # Requires both weekly_summary AND enable_ai_insight to be enabled.
  # Soft-fails on any error — the weekly summary still works without an insight.
  #
  # @param ctx [Hash] pipeline context
  # @param deal [Deal] the target deal
  # @return [Boolean] always true
  def generate_weekly_insight(ctx, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :generate_weekly_insight) if report

    unless enabled?("weekly_summary") && enabled?("enable_ai_insight")
      mark_step_skipped(report, :generate_weekly_insight, message: "Disabled") if report
      return true
    end

    deltas = ctx[:period_deltas] || {}
    stagnation = ctx[:stagnation_breakdown] || {}
    tasks = ctx[:tasks_summary] || {}
    charts = ctx[:charts_data] || {}

    summary_data = {
      deal_name: deal.name,
      new_investors: deltas.dig(:new_investors, :count) || 0,
      total_transitions: deltas.dig(:step_transitions, :total) || 0,
      top_transitions: deltas.dig(:step_transitions, :transitions)&.first(3),
      total_stagnant: stagnation[:total] || 0,
      newly_stagnant: stagnation[:newly_stagnant_count] || 0,
      overdue_tasks: tasks[:overdue_count] || 0,
      funnel: charts[:funnel]
    }

    prompt = <<~PROMPT
      You are a deal pipeline analyst for a fund management firm.
      Based on this week's data for the deal "#{deal.name}", write ONE actionable
      sentence (max 30 words) recommending what the team should focus on next week.
      Be specific — mention step names, investor counts, or stagnation trends.
      No generic advice.

      Data: #{summary_data.to_json}
    PROMPT

    response = ctx[:llm].ask(prompt)
    ctx[:weekly_insight] = extract_text_content(response).strip

    if report
      mark_step_success(report, :generate_weekly_insight,
                        message: ctx[:weekly_insight].truncate(80))
    end
    alert_user(ctx, "AI Insight: #{ctx[:weekly_insight].truncate(100)}", :info)
    true
  rescue StandardError => e
    Rails.logger.error { "[DealManagementAgent] Weekly insight failed: #{e.message}" }
    ctx[:weekly_insight] = nil
    mark_step_failed(report, :generate_weekly_insight, message: e.message) if report
    alert_user(ctx, "AI Insight: failed — #{e.message}", :warning)
    true
  end

  # ── Step 11 ── Pipeline digest + optional blocker alert to notify_email.
  # Runs only when notify_email is present. Always returns true.
  def send_email_digest(ctx, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :send_email_digest) if report

    alert_user(ctx, "Email Digest: preparing pipeline digest…", :info)
    notify_email = @support_agent.json_fields["notify_email"].to_s.strip
    if notify_email.blank?
      ctx[:issues][:digest_issues] << {
        type: :info,
        severity: :success,
        message: "notify_email not configured — digest skipped"
      }
      mark_step_skipped(report, :send_email_digest, message: "No notify_email configured") if report
      alert_user(ctx, "Email Digest: no notify_email configured — skipped", :info)
      return true
    end

    has_blocking = ctx[:issues].values.flatten.any? { |i| i[:severity] == :blocking }

    DealManagementDigestMailer.with(
      support_agent_id: @support_agent.id,
      deal_id: deal.id,
      notify_email: notify_email,
      progress_issues: ctx[:issues][:progress_issues],
      document_issues: ctx[:issues][:document_issues],
      extracted_terms: ctx[:extracted_terms],
      score_leaderboard: ctx[:score_leaderboard] || [],
      health_scores: ctx[:health_scores] || {},
      has_blocking: has_blocking
    ).pipeline_digest.deliver_later

    ctx[:issues][:digest_issues] << {
      type: :info,
      severity: :success,
      message: "Pipeline digest queued to #{notify_email}#{' (includes blocker alert)' if has_blocking}"
    }
    Rails.logger.info { "[DealManagementAgent] Digest queued to #{notify_email}" }
    mark_step_success(report, :send_email_digest, message: "Sent to #{notify_email}") if report
    alert_user(ctx, "Email Digest: sent to #{notify_email}#{has_blocking ? ' ⚠ blockers included' : ' ✓'}", has_blocking ? :warning : :success)
    if enabled?("weekly_summary") && notify_email.present?
      weekly_params = JSON.parse({
        support_agent_id: @support_agent.id,
        deal_id: deal.id,
        notify_email: notify_email,
        period_deltas: ctx[:period_deltas],
        stagnation_breakdown: ctx[:stagnation_breakdown],
        tasks_summary: ctx[:tasks_summary],
        weekly_insight: ctx[:weekly_insight]
      }.to_json)
      DealManagementDigestMailer.with(weekly_params).weekly_summary.deliver_later

      ctx[:issues][:digest_issues] << {
        type: :info,
        severity: :success,
        message: "Weekly summary queued to #{notify_email}"
      }
      Rails.logger.info { "[DealManagementAgent] Weekly summary queued to #{notify_email}" }
    end

    true
  rescue StandardError => e
    Rails.logger.error { "[DealManagementAgent] Digest email failed: #{e.message}" }
    ctx[:issues][:digest_issues] << { type: :error, severity: :success, message: "Digest failed: #{e.message}" }
    mark_step_failed(report, :send_email_digest, message: e.message) if report
    alert_user(ctx, "Email Digest: failed — #{e.message}", :danger)
    true # email failure must not block report save
  end

  # ── Step 12 ── Save deal-level SupportAgentReport. Always runs.
  # Extends base class report with extracted_terms, leaderboard, and cache fields.
  # Creates a new report each run (not upsert) so history accumulates.
  # mark_as_latest! flips the latest flag on the new record and clears it on all prior ones.
  def generate_progress_reports(ctx, support_agent:, deal: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :generate_progress_reports) if report

    alert_user(ctx, "Saving report for '#{deal&.name}'…", :info)

    ctx[:issues].each_value { |issues| issues.reject! { |i| i[:message].blank? } }

    has_blocking = ctx[:issues].values.flatten.any? { |i| i[:severity] == :blocking }

    # Use the step-tracking report (from initialize_report_with_steps) if available,
    # otherwise find or create one (non-step scheduled/batch runs).
    report ||= SupportAgentReport.find_or_initialize_by(owner: deal, support_agent: support_agent)

    # Merge issues data into existing json_fields — preserves steps from initialize_report_with_steps
    report.json_fields = (report.json_fields || {}).merge(ctx[:issues].transform_keys(&:to_s)).merge(
      "final_status" => has_blocking ? "blocked" : "ready",
      "completed_at" => Time.current.iso8601,
      "run_at" => ctx[:run_at] || Time.current.iso8601,
      "extracted_terms" => ctx[:extracted_terms],
      "term_extraction_fingerprint" => ctx[:term_extraction_fingerprint],
      "term_extraction_prompt_used" => ctx[:term_extraction_prompt_used],
      "score_leaderboard" => ctx[:score_leaderboard] || [],
      "health_scores" => ctx[:health_scores] || {}
    )

    # Merge weekly summary data into report
    if enabled?("weekly_summary")
      report.json_fields = report.json_fields.merge(
        "period_deltas" => ctx[:period_deltas],
        "stagnation_breakdown" => ctx[:stagnation_breakdown],
        "tasks_summary" => ctx[:tasks_summary],
        "charts_data" => ctx[:charts_data],
        "weekly_insight" => ctx[:weekly_insight]
      )
    end

    report.status = has_blocking ? :failed : :completed
    report.save!
    report.mark_as_latest!

    ctx[:support_agent_report] = report

    if report
      mark_step_success(report, :generate_progress_reports, message: "Report ##{report.id} saved")
      finalize_report(report, status: has_blocking ? "blocked" : "ready")
    end

    Rails.logger.info { "[DealManagementAgent] Report ##{report.id} saved (latest=true) for Deal##{deal&.id}" }
    alert_user(ctx, "Deal Management Agent complete#{has_blocking ? ' — blockers found, check the report' : ' ✓'}", has_blocking ? :warning : :success)
    true
  rescue StandardError => e
    Rails.logger.error { "[DealManagementAgent] Failed to save report: #{e.message}" }
    mark_step_failed(report, :generate_progress_reports, message: e.message) if report
    true
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  # Broadcasts a real-time UserAlert toast to the triggering user (if user_id present).
  # level: :info | :success | :warning | :danger
  def alert_user(ctx, message, level = :info)
    user_id = ctx[:user_id]
    return if user_id.blank?

    UserAlert.new(user_id: user_id, message: message, level: level.to_s).broadcast
  rescue StandardError => e
    Rails.logger.warn { "[DealManagementAgent] UserAlert failed: #{e.message}" }
  end

  # Returns active DealInvestors — excludes Declined and Complete statuses.
  def active_deal_investors(deal)
    deal.deal_investors
        .where.not(status: %w[Declined Complete])
        .includes(:deal_activities)
  end

  # Counts investors added to the deal within the report period.
  #
  # @param deal [Deal]
  # @return [Hash] count and list of new investors
  def count_new_investors(deal)
    investors = deal.deal_investors.where(created_at: @period_start..@period_end)
    {
      count: investors.count,
      investors: investors.map { |di| { id: di.id, name: di.investor_name, created_at: di.created_at.iso8601 } }
    }
  end

  # Queries the audits table for deal_activity_id changes on this deal's investors.
  # Optionally filters by preset_steps config.
  #
  # @param deal [Deal]
  # @return [Hash] transitions array, details, and total count
  def compute_step_transitions(deal, di_ids, period_audits)
    return { transitions: [], details: [], total: 0 } if di_ids.empty?

    relevant_audits = period_audits.select { |a| a.audited_changes.key?("deal_activity_id") }

    templates = DealActivity.where(deal_id: deal.id, deal_investor_id: nil)
                            .order(:sequence)
                            .pluck(:id, :title, :sequence)
    template_map = templates.to_h { |id, title, _seq| [id, title] }
    sequence_map = templates.to_h { |id, _title, seq| [id, seq] }

    preset_steps = parse_preset_steps
    # Pre-load investor names to avoid N+1 inside the audit loop
    name_map = DealInvestor.where(id: di_ids).pluck(:id, :investor_name).to_h
    transitions = Hash.new(0)
    details = []

    relevant_audits.each do |audit|
      old_id, new_id = audit.audited_changes["deal_activity_id"]
      from_title = template_map[old_id] || "—"
      to_title = template_map[new_id] || "Completed"
      from_seq = sequence_map[old_id]
      to_seq = sequence_map[new_id] || 0

      next if preset_steps.any? && preset_steps.none? { |ps| ps[:from] == from_seq && ps[:to] == to_seq }

      key = "#{from_title} → #{to_title}"
      transitions[key] += 1
      details << {
        investor_id: audit.auditable_id,
        investor_name: name_map[audit.auditable_id],
        from_step: from_title,
        to_step: to_title,
        from_sequence: from_seq,
        to_sequence: to_seq,
        changed_at: audit.created_at.iso8601
      }
    end

    {
      transitions: transitions.sort_by { |_, count| -count },
      details: details,
      total: details.size
    }
  end

  # Queries audits for investor status changes within the report period.
  # Optionally filters by preset_statuses config.
  #
  # @param deal [Deal]
  # @return [Hash] changes grouped by status, with details and total
  def compute_status_changes(_deal, di_ids, period_audits)
    return { by_status: {}, details: {}, total: 0 } if di_ids.empty?

    relevant_audits = period_audits.select { |a| a.audited_changes.key?("status") }

    preset_statuses = @support_agent.json_fields["preset_statuses"].to_s
                                    .split(",").map(&:strip).compact_blank

    name_map = DealInvestor.where(id: di_ids).pluck(:id, :investor_name).to_h
    changes = Hash.new { |h, k| h[k] = [] }

    relevant_audits.each do |audit|
      _old_status, new_status = audit.audited_changes["status"]
      next if preset_statuses.any? && preset_statuses.exclude?(new_status)

      changes[new_status] << {
        investor_id: audit.auditable_id,
        investor_name: name_map[audit.auditable_id],
        changed_at: audit.created_at.iso8601
      }
    end

    {
      by_status: changes.transform_values(&:count),
      details: changes,
      total: changes.values.sum(&:count)
    }
  end

  # Parses preset_steps config: "1-2,3-4" → [{ from: 1, to: 2 }, { from: 3, to: 4 }]
  #
  # @return [Array<Hash>] parsed step transition pairs
  def parse_preset_steps
    raw = @support_agent.json_fields["preset_steps"].to_s.strip
    return [] if raw.blank?

    raw.split(",").filter_map do |pair|
      parts = pair.strip.split("-").map(&:to_i)
      next unless parts.size == 2

      { from: parts[0], to: parts[1] }
    end
  end

  # Formats a Task record into a serialisable hash for the weekly summary report.
  #
  # @param task [Task, nil]
  # @return [Hash, nil]
  def format_deal_task(task)
    return nil unless task

    company_name = (task.owner&.investor_name if task.owner_type == "DealInvestor")

    {
      id: task.id,
      # Strip HTML tags from raw details column (some tasks store Trix HTML)
      title: ActionController::Base.helpers.strip_tags(task.read_attribute(:details).to_s).squish.truncate(80),

      company_name: company_name,
      responsible: task.assigned_to&.name,
      due_date: task.due_date&.iso8601,
      completed: task.completed,
      category: task.category,
      status: if task.completed
                "Completed"
              else
                (task.due_date && task.due_date < Time.zone.today ? "Overdue" : "Pending")
              end
    }
  end

  # Resolves note_period config to an absolute date range.
  def resolve_period
    period = @support_agent.json_fields["note_period"].presence || "Quarter"
    case period.downcase
    when "month"
      prev        = Time.zone.today.prev_month
      start_date  = prev.beginning_of_month
      end_date    = prev.end_of_month
      label       = "Month"
    else
      prev_q_last = Time.zone.today.beginning_of_quarter - 1.day
      start_date  = prev_q_last.beginning_of_quarter
      end_date    = prev_q_last.end_of_quarter
      label       = "Quarter"
    end
    [start_date, end_date, label]
  end

  # Runs the full inner loop for a single DealInvestor.
  def process_single_investor(ctx, di, period_start, period_end, period_label, score_leaderboard)
    Rails.logger.info { "[DealManagementAgent] Processing #{di.investor_name} (DealInvestor##{di.id})" }

    docs     = collect_investor_documents(di, period_start, period_end)
    doc_text = format_documents_for_prompt(docs)

    summary_text = nil
    score_data   = nil

    # summarize_notes requires documents (nothing to summarise without them)
    summary_text = generate_investor_summary(ctx, di, doc_text, period_label) if docs.any? && enabled?("summarize_notes")

    # score_investors can run even without documents — activity history and notes provide signal
    if enabled?("score_investors")
      score_data = score_investor(ctx, di, doc_text, summary_text)
    else
      Rails.logger.info { "[DealManagementAgent] score_investors disabled — skipping for #{di.investor_name}" } unless docs.empty?
    end

    if score_data
      # Write back to DealInvestor (update_columns bypasses validations/callbacks — safe here)
      if di.class.column_names.include?("ai_score")
        di.update_columns(
          ai_score: score_data["overall_score"].to_i,
          ai_grade: score_data["grade"].to_s.first(10)
        )
      end

      score_leaderboard << {
        investor_id: di.id,
        investor_name: di.investor_name,
        status: di.status,
        ai_score: score_data["overall_score"].to_i,
        ai_grade: score_data["grade"].to_s
      }
    end

    Rails.logger.info { "[DealManagementAgent] No documents for #{di.investor_name} — summary skipped" } if docs.empty?

    save_investor_report(
      di, score_data,
      docs.any? ? "ready" : "skipped",
      period_label,
      summary_text: summary_text,
      document_count: docs.size,
      activity_count: di.deal_activities.count
    )
  end

  # Collects documents from the investor's folder and completed activity attachments.
  def collect_investor_documents(di, period_start, _period_end)
    docs = Document
           .where(owner_type: "DealInvestor", owner_id: di.id)
           .to_a

    # Completed activity attachments within the note_period window
    completed_ids = DealActivity
                    .where(deal_investor_id: di.id, status: "complete")
                    .where(updated_at: period_start..)
                    .pluck(:id)

    docs += Document.where(owner_type: "DealActivity", owner_id: completed_ids).to_a if completed_ids.any?

    # Keep only supported file types
    docs.select { |d| d.file.present? && SUPPORTED_EXTENSIONS.include?(File.extname(d.file.original_filename.to_s).downcase) }
  end

  # Reads and formats documents for the LLM prompt, respecting per-doc and total char limits.
  def format_documents_for_prompt(docs)
    return "" if docs.blank?

    total = 0
    parts = []

    docs.each do |doc|
      break if total >= CHARS_TOTAL

      text = read_document_text(doc)
      next if text.blank?

      text = text.first(CHARS_PER_DOC) if text.length > CHARS_PER_DOC
      total += text.length
      parts << "=== #{doc.name} ===\n#{text}"
    rescue StandardError => e
      Rails.logger.warn { "[DealManagementAgent] Skipped '#{doc.name}': #{e.message}" }
    end

    Rails.logger.warn { "[DealManagementAgent] Document text truncated at #{CHARS_TOTAL} chars" } if total >= CHARS_TOTAL
    parts.join("\n\n---\n\n")
  end

  # LLM summary call for a single investor. Returns nil on failure (soft-fail).
  def generate_investor_summary(ctx, di, doc_text, period_label)
    prompt   = build_summary_prompt(di.investor_name, ctx[:deal].name, period_label, doc_text)
    response = ctx[:llm].ask(prompt)
    extract_text_content(response)
  rescue StandardError => e
    Rails.logger.error { "[DealManagementAgent] Summary failed for #{di.investor_name}: #{e.message}" }
    nil
  end

  # LLM scoring call for a single investor. Returns parsed score hash or nil on failure.
  # scoring_skill_file is optional — falls back to DEFAULT_SCORING_RUBRIC when not uploaded.
  def score_investor(ctx, di, doc_text, summary_text)
    skill_content = nil
    skill_doc     = scoring_skill_file_doc

    if skill_doc
      skill_content = read_document_text(skill_doc)
      Rails.logger.warn { "[DealManagementAgent] scoring_skill_file is empty — using default rubric" } if skill_content.blank?
    end

    skill_content = DEFAULT_SCORING_RUBRIC if skill_content.blank?

    min_pts  = [@support_agent.json_fields["min_points_per_section"].to_i, 3].max
    prompt   = build_scoring_prompt(di, ctx[:deal], skill_content, doc_text, summary_text, min_pts)
    response = ctx[:llm].ask(prompt)
    score    = extract_score_json(extract_text_content(response))

    Rails.logger.info { "[DealManagementAgent] Score for #{di.investor_name}: #{score['overall_score']} #{score['grade']}" }
    score
  rescue StandardError => e
    Rails.logger.error { "[DealManagementAgent] Scoring failed for #{di.investor_name}: #{e.message}" }
    nil
  end

  # Upserts the per-investor SupportAgentReport (overwrites on re-run).
  def save_investor_report(di, score_data, final_status, period_label, **extra)
    report        = SupportAgentReport.new(owner: di, support_agent: @support_agent)
    report.status = final_status == "failed" ? :failed : :completed
    report.json_fields = {
      "final_status" => final_status,
      "summary_text" => extra[:summary_text].to_s,
      "score" => score_data,
      "document_count" => extra[:document_count].to_i,
      "activity_count" => extra[:activity_count].to_i,
      "period_label" => period_label,
      "error" => extra[:error],
      "run_at" => Time.current.iso8601,
      "completed_at" => Time.current.iso8601
    }.compact
    report.json_fields_will_change!
    report.save!
    report.mark_as_latest!
  rescue StandardError => e
    Rails.logger.error { "[DealManagementAgent] Failed to save investor report for DealInvestor##{di.id}: #{e.message}" }
  end

  # Resolves the uploaded scoring skill file document from the agent's custom fields.
  def scoring_skill_file_doc
    fcf = @support_agent.form_custom_fields.find { |f| f.field_type == "File" && f.name == "scoring_skill_file" }
    return nil unless fcf

    @support_agent.documents.find_by(name: fcf.human_label)
  end

  # SHA1 fingerprint of sorted "id:updated_at" pairs — changes whenever any doc is added, removed, or updated.
  def compute_doc_fingerprint(docs)
    Digest::SHA1.hexdigest(
      docs.sort_by(&:id).map { |d| "#{d.id}:#{d.updated_at.to_i}" }.join("|")
    )
  end

  # Downloads a Document record and extracts its text content.
  # Returns nil on any failure so callers can safely skip unreadable files.
  def read_document_text(doc)
    return nil if doc&.file.blank?

    extension = File.extname(doc.file.original_filename.to_s).downcase
    result    = nil

    Dir.mktmpdir("deal_agent_") do |tmp_dir|
      filename  = File.basename(doc.file.original_filename.to_s).gsub(/[^0-9A-Za-z.\-_]/, "_")
      file_path = File.join(tmp_dir, filename)
      doc.file.open { |io| File.binwrite(file_path, io.read) }
      result = extract_text_from_file(file_path, extension)
    end

    result
  rescue StandardError => e
    Rails.logger.warn { "[DealManagementAgent] Cannot read '#{doc.name}': #{e.message}" }
    nil
  end

  # Extracts plain text from a file on disk by extension.
  # Mirrors PortfolioScoringAgent's implementation, extended with .docx support.
  def extract_text_from_file(file_path, extension)
    case extension
    when ".txt", ".md"
      File.read(file_path, encoding: "UTF-8")
    when ".csv"
      File.read(file_path, encoding: "UTF-8").lines.first(200).join
    when ".pdf"
      require "pdf-reader"
      PDF::Reader.new(file_path).pages.map(&:text).join("\n\n")
    when ".xlsx", ".xls"
      require "roo"
      spreadsheet = Roo::Spreadsheet.open(file_path)
      spreadsheet.sheets.first(5).flat_map do |sheet_name|
        rows = []
        spreadsheet.sheet(sheet_name).each_row_streaming(pad_cells: true, max_rows: 200) do |row|
          vals = row.map { |c| c&.value.to_s.strip }.compact_blank
          rows << vals.join(" | ") if vals.any?
        end
        ["=== Sheet: #{sheet_name} ===", *rows]
      end.join("\n")
    when ".pptx", ".ppt"
      require "zip"
      require "nokogiri"
      parts = []
      Zip::File.open(file_path) do |zip|
        zip.glob("ppt/slides/slide*.xml")
           .sort_by { |e| e.name.match(/slide(\d+)\.xml/)[1].to_i }
           .each_with_index do |entry, i|
          xml   = Nokogiri::XML(entry.get_input_stream.read).tap(&:remove_namespaces!)
          texts = xml.xpath("//t").map(&:text).compact_blank
          parts << "=== Slide #{i + 1} ===\n#{texts.join("\n")}" if texts.any?
        end
      end
      parts.join("\n\n")
    when ".docx", ".doc"
      # DOCX is a ZIP containing word/document.xml with <w:t> text run nodes
      require "zip"
      require "nokogiri"
      result = ""
      Zip::File.open(file_path) do |zip|
        entry = zip.find_entry("word/document.xml")
        if entry
          xml    = Nokogiri::XML(entry.get_input_stream.read).tap(&:remove_namespaces!)
          result = xml.xpath("//t").map(&:text).join(" ")
        end
      end
      result
    end
  rescue StandardError => e
    Rails.logger.warn { "[DealManagementAgent] extract_text_from_file #{extension}: #{e.message}" }
    nil
  end

  # Unwraps an LLM response object to a plain string.
  def extract_text_content(response)
    return response.to_s unless response.respond_to?(:content)

    content = response.content
    content.is_a?(RubyLLM::Content) ? content.text : content.to_s
  end

  # Extracts and validates a JSON score object from the LLM response.
  def extract_score_json(raw)
    match = raw.match(/```json\s*(\{.+?\})\s*```/m) ||
            raw.match(/```\s*(\{.+?\})\s*```/m) ||
            raw.match(/(\{.+\})/m)
    raise "No JSON block found in LLM response" unless match

    parsed = JSON.parse(match[1])
    validate_score_keys!(parsed)
    parsed
  end

  def validate_score_keys!(parsed)
    missing = REQUIRED_SCORE_KEYS.reject { |k| parsed.key?(k) }
    raise "Score JSON missing required keys: #{missing.join(', ')}" if missing.any?
    raise "overall_score must be 0–100"            unless parsed["overall_score"].to_i.between?(0, 100)
    raise "dimensions must be a non-empty array"   unless parsed["dimensions"].is_a?(Array) && parsed["dimensions"].any?
  end

  # ── Prompt builders ────────────────────────────────────────────────────────

  def build_term_extraction_prompt(custom_prompt, doc_text)
    if custom_prompt.present?
      <<~PROMPT
        You are a deal analyst. Extract the following information from the documents below.

        #{custom_prompt}

        Rules:
        - Return ONLY a valid JSON object.
        - Use null for any field not found in the documents.
        - No explanation, no markdown prose outside the JSON.

        === DOCUMENTS ===
        #{doc_text}
      PROMPT
    else
      <<~PROMPT
        You are a deal analyst. Extract the following deal terms from the documents below.
        Return ONLY a valid JSON object. Use null for any field not found.

        Fields to extract:
          pre_money_valuation, post_money_valuation, equity_percentage,
          investment_amount, instrument_type, closing_date, board_seats,
          pro_rata_rights, anti_dilution, rofr, drag_along, lock_up_period

        === DOCUMENTS ===
        #{doc_text}
      PROMPT
    end
  end

  def build_summary_prompt(investor_name, deal_name, period, doc_text)
    <<~PROMPT
      You are a deal manager's assistant. Summarize the documents and activity notes
      below for investor #{investor_name} in deal #{deal_name} (#{period}).

      Write three sections:

      1. Key Themes
         Bullet points covering recurring topics and developments.

      2. Action Items
         Bullet points listing specific follow-ups or commitments.
         Write "None identified" if there are none.

      3. Investor Engagement
         One of: Actively Engaged / In Progress / Stalled
         Follow with one sentence of justification.

      Rules: Be concise. Do not invent facts not present in the documents.
      Plain prose only — no markdown code fences.

      === DOCUMENTS ===
      #{doc_text}
    PROMPT
  end

  def build_scoring_prompt(di, deal, skill_content, doc_text, summary_text, min_pts)
    activity_lines = di.deal_activities.map do |act|
      days_overdue = act.by_date.present? ? (Time.zone.today - act.by_date).to_i : nil
      overdue_str  = days_overdue.present? && days_overdue.positive? ? "+#{days_overdue}d overdue" : nil
      [act.title, act.status, act.by_date, overdue_str].compact.join(" | ")
    end.join("\n")

    notes_text = di.notes.respond_to?(:to_plain_text) ? di.notes.to_plain_text.strip : di.notes.to_s.strip

    <<~PROMPT
      #{skill_content}

      ---

      Score the investor below using all available data.

      Investor : #{di.investor_name}
      Deal     : #{deal.name}

      ### Investor Details
      #{di.status} | #{di.tier} | #{di.primary_amount&.format} | Source: #{di.source} | Tags: #{di.tags}

      ### Activity History
      #{activity_lines.presence || 'No activities recorded.'}

      ### Documents
      #{doc_text.presence || 'No documents available.'}

      ### Notes
      #{notes_text.presence || 'No notes recorded.'}

      #{"### AI Summary\n#{summary_text}\n" if summary_text.present?}

      ---

      Return a single JSON object with these keys:

      {
        "overall_score": <integer 0-100>,
        "grade":         <string e.g. "B+">,
        "summary":       <string - one paragraph narrative>,
        "dimensions": [
          {
            "name":      <string>,
            "score":     <integer 0-100>,
            "weight":    <number>,
            "rationale": <string>,
            "positives": [<at least #{min_pts} specific, data-backed positives>],
            "concerns":  [<at least #{min_pts} specific, data-backed concerns>]
          }
        ],
        "strengths":       [<at least #{min_pts} items>],
        "risks":           [<at least #{min_pts} items>],
        "recommendations": [<at least #{min_pts} items>]
      }

      Wrap the JSON in ```json ... ``` fences. Return nothing else.
    PROMPT
  end
end
