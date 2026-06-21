# frozen_string_literal: true

require 'shellwords'

# PresentationAnalystAgent — reads investor presentations attached to
# KpiReports and produces three outputs per portfolio company:
#
#   1. Structured intelligence per period (commitments, risks, metrics, etc.)
#   2. Cross-period flags (what changed, disappeared, or doesn't add up)
#   3. Pre-board briefing (8–12 grounded analyst questions)
#   4. Management Accountability Score (pure arithmetic, no extra LLM call)
#
# Architecture follows PortfolioScoringAgent exactly:
#   - Trailblazer steps with direct ctx[:llm].ask() calls
#   - Inline document reading via read_document_text / extract_text_from_file
#   - SupportAgentReport.json_fields for all output — no new DB tables
#   - process_batch for batch/scheduled runs, wtf? for adhoc/single runs
#
# PRD: docs/ai/investor_presentation_analyst_prd.md
# PRD §11 — Architecture, §12 — New Components, §13 — Data Storage
class PresentationAnalystAgent < SupportAgentService
  DESCRIPTION = "Reads investor presentations across periods, flags what changed, " \
                "and generates a pre-board briefing + Management Accountability Score."

  LONG_DESCRIPTION = <<~DESC
    Reads investor presentation documents (PDF, PPTX, DOCX) from a portfolio company's
    KpiReports, extracts structured intelligence per period, then compares across periods
    to surface commitment misses, dropped risks, objective drift, abandoned initiatives,
    and metric anomalies. Produces a pre-board briefing (8–12 grounded questions) and a
    Management Accountability Score (0–100).

    Steps:
    • Collect Presentations — finds KPI report documents whose names match the
      presentation_doc_names CSV config (default: "Investor Update, Board Deck, ...").
    • Extract Intelligence — reads each matched document in full (gemini-3-flash, 1M
      token context) and extracts 8 structured categories per period.
    • Cross-Period Analysis — one LLM call across all period records (or sliding-window
      pairs for cost saving) to produce five comparison lenses.
    • Generate Briefing — 8–12 grounded questions. Skipped and reused from the previous
      run when cross-period flags have not changed (SHA-256 digest check).
    • Score — pure arithmetic from the flags. No additional LLM call.
    • Save — persists everything to SupportAgentReport.json_fields.

    Config: presentation_doc_names (CSV), max_periods (default 8), kpi_tag_list
    (default Actual), comparison_strategy (all_periods | sliding_window),
    llm_model (default gemini-3-flash).

    PRD: docs/ai/investor_presentation_analyst_prd.md
  DESC

  # PRD §12.1 — Configuration. These match the agent's FormType custom fields.
  # Human-readable labels shown in the Trailblazer step progress panel.
  STEP_LABELS = {
    initialize_agent: "Initialize",
    collect_presentations: "Collect Presentations",
    extract_intelligence: "Extract Intelligence",
    compare_across_periods: "Cross-Period Analysis",
    generate_analyst_qs: "Generate Briefing",
    compute_scores: "Score",
    store_results: "Save"
  }.freeze

  # All file types the agent will attempt to read. PPTX/DOCX go through a
  # three-tier fallback: LibreOffice → Pandoc → Nokogiri (PRD §12.2).
  SUPPORTED_DOC_EXTENSIONS = %w[.pdf .txt .md .xlsx .xls .pptx .ppt .docx .doc].freeze

  # PRD §4.1 — default document names matched case-insensitively against document.name.
  # Overridden via the presentation_doc_names CSV custom field.
  DEFAULT_DOC_NAMES = [
    "Investor Update",
    "Board Deck",
    "Management Presentation",
    "Quarterly Update",
    "Investor Presentation"
  ].freeze

  # Trailblazer step pipeline — each step must return truthy to continue.
  # Returning false anywhere after initialize_agent stops the pipeline and
  # leaves store_results to persist the partial state.
  step :initialize_agent
  step :collect_presentations
  step :extract_intelligence
  step :compare_across_periods
  step :generate_analyst_qs
  step :compute_scores
  step :store_results

  # Returns portfolio companies for batch runs, or wraps a single Investor for adhoc.
  # PRD §11 — Execution modes.
  def targets(entity_id)
    if entity_id.is_a?(Investor) || entity_id.is_a?(ActiveRecord::Base)
      [entity_id]
    else
      Investor.where(entity_id: entity_id, category: "Portfolio Company")
    end
  end

  # Sequential batch processor — mirrors PortfolioScoringAgent.process_batch exactly.
  # :scheduled mode suppresses the batch summary notification.
  # PRD §11 — BATCH / SCHEDULED execution mode.
  def self.process_batch(support_agent_id:, targets:, user_id:, entity_id:, with_steps: false, execution_mode: :adhoc_batch)
    support_agent = SupportAgent.find(support_agent_id)

    # Preload KPI reports to avoid N+1 queries when iterating companies
    targets = targets.includes(:portfolio_kpi_reports) if targets.respond_to?(:includes)

    successes = []
    errors    = []

    targets.to_a.each do |target|
      support_agent.agent.wtf?(
        support_agent_id: support_agent_id,
        target: target,
        user_id: user_id,
        entity_id: entity_id,
        batch_mode: true
      )
      successes << { id: target.id, name: target.try(:investor_name) || "ID=#{target.id}" }
    rescue StandardError => e
      Rails.logger.error { "[PresentationAnalystAgent] process_batch error for ID=#{target.id}: #{e.message}" }
      errors << { target_id: target.id, target_name: target.try(:investor_name) || "ID=#{target.id}", error: e.message }
    end

    # Only notify on adhoc runs; scheduled runs generate their own digest emails separately
    if execution_mode != :scheduled
      begin
        batch_target_type = targets.first.class.name if targets.any?
        SupportAgentJob.new.send(:send_batch_summary, support_agent, successes, errors, user_id, batch_target_type) if defined?(SupportAgentJob)
      rescue StandardError => e
        Rails.logger.error { "[PresentationAnalystAgent] failed to send batch summary: #{e.message}" }
      end
    end

    { successes: successes, errors: errors }
  end

  private

  # ─── Step 1: Initialize ──────────────────────────────────────────────────────

  # Calls super to load @support_agent and ctx[:llm], then checks the agent is
  # enabled and the target is a portfolio company (not an LP or fund).
  def initialize_agent(ctx, target: nil, **)
    super # sets @support_agent, ctx[:support_agent], ctx[:llm] via SupportAgentService

    report = ctx[:support_agent_report]
    mark_step_running(report, :initialize_agent) if report

    ctx[:investor]       = target
    ctx[:period_records] = [] # accumulated per-period extracted records
    ctx[:issues]         = { collection_issues: [], extraction_issues: [], analysis_issues: [] }

    Rails.logger.info { "[PresentationAnalystAgent] Initializing for #{target&.investor_name} (ID=#{target&.id})" }

    mark_step_success(report, :initialize_agent, message: "Initialized for #{target&.investor_name}") if report

    # Returning false here short-circuits the pipeline with no error — correct
    # behaviour when the agent is disabled or the target is not a portfolio company
    target.category == "Portfolio Company" && @support_agent.enabled?
  end

  # ─── Step 2: Collect Presentations ───────────────────────────────────────────

  # Finds KPI reports of the configured tag (default: Actual) for the most recent
  # max_periods periods, then locates the first document in each report whose name
  # matches the presentation_doc_names CSV.
  #
  # PRD §12.1 — presentation_doc_names, max_periods, kpi_tag_list config fields.
  def collect_presentations(ctx, investor: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :collect_presentations) if report

    allowed_names = presentation_doc_names # from custom field CSV, or DEFAULT_DOC_NAMES
    tag_list      = @support_agent.json_fields["kpi_tag_list"].presence || "Actual"
    max_periods = @support_agent.json_fields["max_periods"].to_i
    max_periods = 8 if max_periods < 1 # guard: treat zero/blank as default

    # Order ascending so extract_intelligence processes oldest → newest (needed for
    # the comparator to understand temporal direction of changes)
    reports = investor.portfolio_kpi_reports
                      .where(tag_list: tag_list)
                      .includes(:documents)
                      .order(as_of: :asc)
                      .last(max_periods)

    # Map each report to its first matching presentation document
    ctx[:presentation_docs] = reports.filter_map do |report|
      doc = report.documents.find do |d|
        d.file.present? &&
          allowed_names.any? { |name| d.name.to_s.downcase.include?(name.downcase) }
      end
      next unless doc

      ext = File.extname(doc.file.original_filename.to_s).downcase
      next unless SUPPORTED_DOC_EXTENSIONS.include?(ext)

      # Bundle document metadata so extract_intelligence has all it needs
      { report: report, document: doc, period_label: report.label }
    end

    if ctx[:presentation_docs].empty?
      # Record as blocking so store_results sets final_status = "blocked".
      # Return true (not false) so the pipeline continues to store_results and persists
      # the blocked state. Subsequent steps handle empty ctx[:presentation_docs] by
      # checking size before making any LLM calls.
      ctx[:issues][:collection_issues] << {
        type: :info,
        message: "No presentation documents found matching: #{allowed_names.join(', ')}",
        severity: :blocking
      }
      mark_step_skipped(report, :collect_presentations, message: "No presentations found") if report
      Rails.logger.warn { "[PresentationAnalystAgent] No presentations found for #{investor.investor_name}" }
      return true
    end

    Rails.logger.info do
      labels = ctx[:presentation_docs].map { |d| d[:period_label] }.join(", ")
      "[PresentationAnalystAgent] Found #{ctx[:presentation_docs].size} presentation(s): #{labels}"
    end
    ctx[:issues][:collection_issues] << {
      type: :info,
      message: "Found #{ctx[:presentation_docs].size} presentation(s) across #{ctx[:presentation_docs].pluck(:period_label).join(', ')}",
      severity: :success
    }
    mark_step_success(report, :collect_presentations, message: "Found #{ctx[:presentation_docs].size} presentation(s)") if report
    true
  end

  # ─── Step 3: Extract Intelligence ────────────────────────────────────────────

  # Reads each matched document in full and calls the LLM to extract eight
  # structured categories. gemini-3-flash has a 1M token context window so we
  # never truncate — the model sees the complete presentation (PRD §4.1).
  #
  # Soft-fail: a single document read/parse error logs and moves on rather than
  # failing the whole company (mirrors NoteSummarizerAgent's soft-fail pattern).
  def extract_intelligence(ctx, investor: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :extract_intelligence) if report

    ctx[:presentation_docs].each do |entry|
      # read_document_text handles download + text extraction; returns nil on failure
      text = read_document_text(entry[:document])

      if text.blank?
        ctx[:issues][:extraction_issues] << {
          type: :info, message: "Could not read #{entry[:period_label]} — skipped", severity: :success
        }
        next
      end

      # Full document text passed directly — no chunking, no truncation.
      # PRD §4.1: "Full document needs to be processed — gemini has a 1M context."
      prompt   = build_extraction_prompt(investor.investor_name, entry[:period_label], text)
      response = ctx[:llm].ask(prompt)
      record   = extract_json_hash(extract_text_content(response))

      if record
        # Attach period metadata so the comparator knows the temporal ordering
        ctx[:period_records] << record.merge(
          "period_label" => entry[:period_label],
          "as_of" => entry[:report].as_of.to_s
        )
        ctx[:issues][:extraction_issues] << {
          type: :info, message: "Extracted #{entry[:period_label]}", severity: :success
        }
      else
        ctx[:issues][:extraction_issues] << {
          type: :info, message: "Unparseable LLM response for #{entry[:period_label]} — skipped", severity: :success
        }
      end
    rescue StandardError => e
      Rails.logger.error { "[PresentationAnalystAgent] Extraction failed for #{entry[:period_label]}: #{e.message}" }
      ctx[:issues][:extraction_issues] << {
        type: :info, message: "Extraction error for #{entry[:period_label]}: #{e.message}", severity: :success
      }
    end

    if ctx[:period_records].empty?
      mark_step_skipped(report, :extract_intelligence, message: "No records extracted") if report
      ctx[:issues][:analysis_issues] << {
        type: :info, message: "No records extracted — analysis skipped", severity: :blocking
      }
      # Return true (not false) so store_results still runs and persists the failure state
      return true
    end

    mark_step_success(report, :extract_intelligence, message: "Extracted #{ctx[:period_records].size} period record(s)") if report
    Rails.logger.info { "[PresentationAnalystAgent] Extracted #{ctx[:period_records].size} period record(s) for #{investor.investor_name}" }
    true
  end

  # ─── Step 4: Cross-Period Analysis ───────────────────────────────────────────

  # Compares all extracted period records to produce five lenses:
  #   commitment_tracker, risk_evolution, objective_drift,
  #   initiative_graveyard, metric_anomalies
  #
  # Two strategies (PRD §12.1 — comparison_strategy config):
  #   all_periods     — one LLM call with all records. More accurate. Default.
  #   sliding_window  — one call per adjacent pair (N-1 → N). Cheaper for many periods.
  def compare_across_periods(ctx, investor: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :compare_across_periods) if report

    # Need at least two periods to compare; single-period runs skip this step
    if ctx[:period_records].size < 2
      mark_step_skipped(report, :compare_across_periods, message: "Only one period") if report
      ctx[:cross_period_flags] = {}
      ctx[:issues][:analysis_issues] << {
        type: :info, message: "Only one period — cross-period analysis skipped", severity: :success
      }
      return true
    end

    strategy = @support_agent.json_fields["comparison_strategy"].presence || "all_periods"

    flags = if strategy == "sliding_window"
              run_sliding_window_comparison(ctx, investor)
            else
              run_all_periods_comparison(ctx, investor)
            end

    ctx[:cross_period_flags] = flags || {}

    total_flags = (flags&.values || []).sum { |v| Array(v).size }
    ctx[:issues][:analysis_issues] << {
      type: :info,
      message: "Cross-period analysis complete (#{strategy}) — #{total_flags} flag(s) across #{ctx[:period_records].size} periods",
      severity: :success
    }
    mark_step_success(report, :compare_across_periods, message: "#{total_flags} flag(s) across #{ctx[:period_records].size} periods") if report
    Rails.logger.info { "[PresentationAnalystAgent] Cross-period analysis: #{total_flags} flags (strategy=#{strategy})" }
    true
  rescue StandardError => e
    Rails.logger.error { "[PresentationAnalystAgent] Comparator failed: #{e.message}" }
    mark_step_failed(report, :compare_across_periods, message: e.message) if report
    ctx[:cross_period_flags] = {} # empty flags → scoring still runs, questions skipped
    true # soft-fail so store_results runs
  end

  # One LLM call covering all periods simultaneously — more accurate because the
  # model sees the full temporal arc. Preferred when period count is small (≤ 8).
  def run_all_periods_comparison(ctx, investor)
    records_json = JSON.pretty_generate(ctx[:period_records])
    prompt       = build_comparator_prompt(investor.investor_name, records_json)
    response     = ctx[:llm].ask(prompt)
    extract_json_hash(extract_text_content(response))
  end

  # One LLM call per adjacent pair (n-1 → n), then merges results.
  # PRD §6: cheaper when the GP has many periods and cost matters more than precision.
  def run_sliding_window_comparison(ctx, investor)
    # Use a Hash with array default so we can concat across pairs
    merged = Hash.new { |h, k| h[k] = [] }

    ctx[:period_records].each_cons(2) do |older, newer|
      pair_json  = JSON.pretty_generate([older, newer])
      pair_flags = extract_json_hash(extract_text_content(ctx[:llm].ask(build_comparator_prompt(investor.investor_name, pair_json)))) || {}
      # Accumulate flags from each pair — dedup by JSON fingerprint at the end
      pair_flags.each { |lens, items| merged[lens].concat(Array(items)) }
    end

    # Deduplicate flags that appear in multiple window pairs
    merged.transform_values { |items| items.uniq(&:to_json) }
  end

  # ─── Step 5: Generate Analyst Questions (Pre-Board Briefing) ─────────────────

  # Generates 8–12 questions grounded in the actual document names/numbers/language.
  # PRD §5 — The Pre-Board Briefing.
  #
  # Digest caching (PRD §12.2): if the cross-period flags haven't changed since the
  # last run (SHA-256 match), we reuse the previous question set with zero LLM cost.
  # This makes re-running the agent cheap on stable portfolios.
  def generate_analyst_qs(ctx, investor: nil, support_agent: nil, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :generate_analyst_qs) if report

    # Nothing to ask if extraction produced no records
    if ctx[:period_records].empty?
      mark_step_skipped(report, :generate_analyst_qs, message: "No records to analyze") if report
      return true
    end

    # Skip if the enable_questions flag is explicitly disabled (default: on)
    unless questions_enabled?
      mark_step_skipped(report, :generate_analyst_qs, message: "Questions disabled") if report
      ctx[:analyst_questions] = []
      ctx[:issues][:analysis_issues] << {
        type: :info, message: "Question generation disabled via enable_questions setting", severity: :success
      }
      return true
    end

    # Initialise early so the rescue block can reference them safely even if an
    # error is raised before their normal assignment points below
    flags_digest   = nil
    prev_questions = nil

    # Compute a fingerprint of the current flags to detect material changes
    flags_json   = JSON.generate(ctx[:cross_period_flags] || {})
    flags_digest = Digest::SHA256.hexdigest(flags_json)

    # Look up the previous run to check if flags are unchanged
    prev_report    = SupportAgentReport
                     .where(owner: investor, support_agent: support_agent)
                     .order(created_at: :desc)
                     .first
    prev_digest    = prev_report&.json_fields&.dig("flags_digest")
    prev_questions = prev_report&.json_fields&.dig("analyst_questions")

    # Reuse previous questions when flags are identical — saves one LLM call per run
    if flags_digest == prev_digest && prev_questions.present?
      ctx[:analyst_questions] = prev_questions
      ctx[:flags_digest]      = flags_digest
      ctx[:issues][:analysis_issues] << {
        type: :info,
        message: "Flags unchanged — reusing #{prev_questions.size} questions from previous run (no LLM call)",
        severity: :success
      }
      mark_step_success(report, :generate_analyst_qs, message: "Reusing #{prev_questions.size} questions") if report
      Rails.logger.info { "[PresentationAnalystAgent] Digest match — skipping question generation for #{investor.investor_name}" }
      return true
    end

    # Flags changed (or first run) — generate fresh questions
    records_json = JSON.pretty_generate(ctx[:period_records])
    prompt       = build_question_prompt(investor.investor_name, records_json, flags_json)
    response     = ctx[:llm].ask(prompt)
    questions    = extract_json_array(extract_text_content(response))

    ctx[:analyst_questions] = questions || []
    ctx[:flags_digest]      = flags_digest
    mark_step_success(report, :generate_analyst_qs, message: "Generated #{ctx[:analyst_questions].size} questions") if report
    ctx[:issues][:analysis_issues] << {
      type: :info,
      message: "Generated #{ctx[:analyst_questions].size} briefing questions",
      severity: :success
    }
    Rails.logger.info { "[PresentationAnalystAgent] Generated #{ctx[:analyst_questions].size} questions for #{investor.investor_name}" }
    true
  rescue StandardError => e
    Rails.logger.error { "[PresentationAnalystAgent] Question generation failed: #{e.message}" }
    mark_step_failed(report, :generate_analyst_qs, message: e.message) if report
    # Fall back to the previous run's questions rather than losing them entirely
    ctx[:analyst_questions] = prev_questions || []
    ctx[:flags_digest]      = flags_digest
    true # soft-fail
  end

  # ─── Step 6: Management Accountability Score ──────────────────────────────────

  # Pure arithmetic from the cross-period flags — zero additional LLM calls.
  # Four dimensions weighted as per PRD §6:
  #   Commitment (35%) + Risk (25%) + Coherence (25%) + Narrative (15%)
  #
  # PRD §6 — Management Accountability Score.
  # PRD §6: "How this differs from PortfolioScoringAgent" — this measures management
  # communication behaviour, not company fundamentals.
  def compute_scores(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :compute_scores) if report

    # Skip if the enable_scoring flag is explicitly disabled (default: on)
    unless scoring_enabled?
      mark_step_skipped(report, :compute_scores, message: "Scoring disabled") if report
      ctx[:score] = nil
      ctx[:issues][:analysis_issues] << {
        type: :info, message: "Scoring disabled via enable_scoring setting", severity: :success
      }
      return true
    end
    flags   = ctx[:cross_period_flags] || {}
    records = ctx[:period_records]

    # Each dimension scorer returns 0–100; the weighted average gives the overall score
    commitment = score_commitments(flags["commitment_tracker"] || [])
    risk       = score_risk(flags["risk_evolution"] || [])
    coherence  = score_coherence(flags["objective_drift"] || [], flags["initiative_graveyard"] || [], records)
    narrative  = score_narrative(flags["metric_anomalies"] || [])

    overall = ((commitment * 0.35) + (risk * 0.25) + (coherence * 0.25) + (narrative * 0.15)).round

    ctx[:score] = {
      "overall_score" => overall,
      "grade" => score_to_grade(overall),
      "commitment_score" => commitment,
      "risk_score" => risk,
      "coherence_score" => coherence,
      "narrative_score" => narrative,
      "periods_analyzed" => records.size
    }

    ctx[:issues][:analysis_issues] << {
      type: :info,
      message: "Management Accountability Score: #{overall}/100 (#{score_to_grade(overall)})",
      severity: :success
    }
    mark_step_success(report, :compute_scores, message: "Score: #{ctx[:score]['overall_score']}/100 (#{ctx[:score]['grade']})") if report
    Rails.logger.info { "[PresentationAnalystAgent] Score: #{overall} #{score_to_grade(overall)} for #{ctx[:investor]&.investor_name}" }
    true
  rescue StandardError => e
    Rails.logger.error { "[PresentationAnalystAgent] Scoring failed: #{e.message}" }
    mark_step_failed(report, :compute_scores, message: e.message) if report
    ctx[:score] = nil
    true # soft-fail — a missing score should not block storing the questions and flags
  end

  # Commitment dimension (weight 35%):
  # Base score = (met + partially_met×0.5) / total. Penalise silent drops.
  # "not_mentioned" = commitment appeared in an earlier period but was never revisited —
  # the most damaging signal (management avoided accountability entirely).
  def score_commitments(tracker)
    return 50 if tracker.empty? # neutral when no commitments were tracked

    met     = tracker.count { |c| c["status"] == "met" }
    partial = tracker.count { |c| c["status"] == "partially_met" }
    at_risk = tracker.count { |c| c["status"] == "at_risk" } # softening but not yet failed
    drops   = tracker.count { |c| c["status"] == "not_mentioned" } # silent drops

    base = ((met + (partial * 0.5) + (at_risk * 0.25)) / tracker.size * 100).round
    (base - (drops * 5)).clamp(0, 100) # silent drops cost 5pts; at_risk counts 0.25 (warning, not failure)
  end

  # Risk dimension (weight 25%):
  # Starts at 100; each flag type adjusts up or down.
  # "dropped" = risk disappeared without a stated resolution — worst case.
  # "resolved" = risk was named and closed — rewarded.
  def score_risk(evolution)
    score = 100
    evolution.each do |r|
      score += case r["status"]
               when "dropped"   then -10  # vanished with no resolution — red flag
               when "escalated" then -5   # risk grew worse — concerning
               when "new"       then -3   # new risk introduced — mild penalty
               when "resolved"  then +5   # risk closed out — positive signal
               else 0
               end
    end
    score.clamp(0, 100)
  end

  # Coherence dimension (weight 25%):
  # Penalises objective drift and initiative abandonment.
  # Rewards consistent objectives that appear across ≥3 periods (stable vision).
  def score_coherence(drift, graveyard, records)
    score = 100
    drift.each do |obj|
      score += case obj["change"]
               when "removed"  then -8  # hardest to justify without explanation
               when "reframed" then -3  # acknowledged pivot, still disruption
               else 0 # "added" objectives are not penalised
               end
    end

    # Each abandoned initiative (named but never completed) costs 5 points
    score -= graveyard.size * 5

    # Reward strategic consistency: objectives appearing in ≥3 periods show stable vision
    if records.size >= 3
      stable_objectives = records
                          .flat_map { |r| Array(r["strategic_objectives"]).map { |o| o["description"].to_s.downcase } }
                          .tally
                          .count { |_, n| n >= 3 }
      score += stable_objectives * 5
    end

    score.clamp(0, 100)
  end

  # Narrative dimension (weight 15%):
  # Each metric anomaly (regression, restatement, arithmetic inconsistency)
  # costs 10 points — this is the most binary of the four dimensions.
  def score_narrative(anomalies)
    (100 - (anomalies.size * 10)).clamp(0, 100)
  end

  # Maps a 0–100 score to the same grade scale as PortfolioScoringAgent
  # so both scores can be compared side-by-side in the UI (PRD §6).
  def score_to_grade(score)
    case score
    when 90..100 then "A"
    when 80..89  then "B+"
    when 70..79  then "B"
    when 60..69  then "C+"
    when 50..59  then "C"
    else              "D"
    end
  end

  # ─── Step 7: Save Results ─────────────────────────────────────────────────────

  # Persists everything to SupportAgentReport.json_fields.
  # PRD §13 — Data Storage. No new DB tables — all data in json_fields.
  #
  # Always creates a new SupportAgentReport so full run history is preserved.
  # after_create :mark_as_latest! on the model atomically demotes previous records
  # (sets latest=false). The chat provider queries order(created_at: :desc).first
  # so it always reads the newest run regardless.
  def store_results(ctx, investor: nil, support_agent: nil, **)
    step_report = ctx[:support_agent_report]
    mark_step_running(step_report, :store_results) if step_report

    has_blocking = ctx[:issues].values.flatten.any? { |i| i[:severity] == :blocking }

    # Clean out blank messages (mirrors SupportAgentService#generate_progress_reports)
    ctx[:issues].each_value { |issues| issues.reject! { |i| i[:message].blank? } }

    report = SupportAgentReport.new(owner: investor, support_agent: support_agent)
    now    = Time.current.iso8601

    report.json_fields = (report.json_fields || {}).merge(
      # The eight-category per-period extracted records (PRD §4.1)
      "period_records" => ctx[:period_records],
      # Five cross-period lenses (PRD §4.2)
      "cross_period_flags" => ctx[:cross_period_flags] || {},
      # Pre-board briefing questions (PRD §5)
      "analyst_questions" => ctx[:analyst_questions] || [],
      # Human-readable list of periods analyzed (shown in score card header)
      "periods_analyzed" => ctx[:period_records].pluck("period_label"),
      # Digest used to decide whether questions need regeneration next run (PRD §5)
      "flags_digest" => ctx[:flags_digest],
      # Management Accountability Score (PRD §6)
      "score" => ctx[:score],
      # Issue arrays from all steps — surfaced in the UI expandable panels
      "collection_issues" => ctx[:issues][:collection_issues],
      "extraction_issues" => ctx[:issues][:extraction_issues],
      "analysis_issues" => ctx[:issues][:analysis_issues],
      "final_status" => has_blocking ? "blocked" : "ready",
      "run_at" => now,
      "completed_at" => now,
      # Persist which features were active during this run so the UI can hide sections accordingly
      "scoring_enabled" => scoring_enabled?,
      "questions_enabled" => questions_enabled?
    )

    # MySQL doesn't track JSON column mutations automatically
    report.json_fields_will_change!
    report.status = has_blocking ? :failed : :completed
    report.save! # after_create callback fires mark_as_latest! atomically

    ctx[:support_agent_report] = report

    if step_report
      mark_step_success(step_report, :store_results, message: "Report ##{report.id} saved")
      finalize_report(step_report, status: has_blocking ? "blocked" : "ready")
    end

    Rails.logger.info { "[PresentationAnalystAgent] Report saved ID=#{report.id} status=#{report.status}" }
    true
  rescue StandardError => e
    Rails.logger.error { "[PresentationAnalystAgent] store_results failed: #{e.message}" }
    mark_step_failed(step_report, :store_results, message: e.message) if step_report
    false
  end

  # ─── Document Reading ─────────────────────────────────────────────────────────
  # Identical to PortfolioScoringAgent — downloaded to a tmp dir, extracted by type.

  # Downloads the Document's attached file to a temp dir and extracts its text.
  # Returns nil on any failure so callers can skip gracefully.
  def read_document_text(doc)
    return nil if doc&.file.blank?

    result = nil
    Dir.mktmpdir("presentation_analyst_") do |tmp_dir|
      # Sanitise the filename to avoid shell injection in LibreOffice commands
      filename  = File.basename(doc.file.original_filename.to_s).gsub(/[^0-9A-Za-z.\-_]/, '_')
      file_path = File.join(tmp_dir, filename)
      doc.file.open { |io| File.binwrite(file_path, io.read) }
      result = extract_text_from_file(file_path, File.extname(filename).downcase)
    end
    result
  rescue StandardError => e
    Rails.logger.warn { "[PresentationAnalystAgent] Could not read '#{doc.name}': #{e.message}" }
    nil
  end

  # Routes to the appropriate extractor by file extension.
  # PPTX/DOCX use a three-tier fallback chain — PRD §12.2.
  def extract_text_from_file(file_path, extension)
    case extension
    when '.txt', '.md'
      File.read(file_path, encoding: 'UTF-8')

    when '.pdf'
      require 'pdf-reader'
      PDF::Reader.new(file_path).pages.map(&:text).join("\n\n")

    when '.xlsx', '.xls'
      require 'roo'
      spreadsheet = Roo::Spreadsheet.open(file_path)
      spreadsheet.sheets.flat_map do |sheet|
        rows = []
        spreadsheet.sheet(sheet).each_row_streaming(pad_cells: true) do |row|
          vals = row.map { |c| c&.value.to_s.strip }.compact_blank
          rows << vals.join(" | ") if vals.any?
        end
        ["=== #{sheet} ===", *rows]
      end.join("\n")

    when '.pptx', '.ppt', '.docx', '.doc'
      # Tier 1: LibreOffice headless — handles speaker notes, tables, grouped shapes
      # Tier 2: Pandoc — simpler but misses some PPTX features
      # Tier 3: Nokogiri XML parse — fast but misses speaker notes and table cells
      extract_via_libreoffice(file_path) ||
        extract_via_pandoc(file_path) ||
        extract_via_nokogiri_pptx(file_path)
    end
  rescue StandardError => e
    "Error extracting #{extension}: #{e.message}"
  end

  # LibreOffice headless: most faithful to the original layout, including notes.
  # Writes a .txt file alongside the source, reads it back.
  def extract_via_libreoffice(file_path)
    return nil unless system("which soffice > /dev/null 2>&1")

    out_dir = File.dirname(file_path)
    system("soffice --headless --convert-to txt:Text --outdir #{Shellwords.shellescape(out_dir)} #{Shellwords.shellescape(file_path)} > /dev/null 2>&1")
    txt_path = file_path.sub(/\.[^.]+$/, '.txt')
    File.exist?(txt_path) ? File.read(txt_path, encoding: 'UTF-8') : nil
  rescue StandardError
    nil # fall through to next tier
  end

  # Pandoc: handles DOCX well; PPTX support is limited
  def extract_via_pandoc(file_path)
    return nil unless system("which pandoc > /dev/null 2>&1")

    output = `pandoc --to plain #{Shellwords.shellescape(file_path)} 2>/dev/null`
    output.presence
  rescue StandardError
    nil # fall through to Nokogiri
  end

  # Nokogiri XML parse: last resort for PPTX — misses speaker notes and tables
  # but handles basic slide text reliably.
  def extract_via_nokogiri_pptx(file_path)
    require 'zip'
    require 'nokogiri'

    parts = []
    Zip::File.open(file_path) do |zip|
      zip.glob('ppt/slides/slide*.xml')
         .sort_by { |entry| entry.name.match(/slide(\d+)\.xml/)&.captures&.first.to_i }
         .each_with_index do |entry, idx|
        xml   = Nokogiri::XML(entry.get_input_stream.read).tap(&:remove_namespaces!)
        texts = xml.xpath('//t').map(&:text).compact_blank
        parts << "=== Slide #{idx + 1} ===\n#{texts.join("\n")}" if texts.any?
      end
    end
    parts.join("\n\n")
  rescue StandardError
    nil
  end

  # ─── Prompt Builders ──────────────────────────────────────────────────────────

  # Extraction prompt: instructs the LLM to return exactly eight structured
  # categories from a single presentation. "Return ONLY the JSON" prevents the
  # model from wrapping the response in explanatory prose.
  #
  # PRD §4.1 — the eight extraction categories.
  def build_extraction_prompt(company_name, period_label, text)
    <<~PROMPT
      You are an experienced venture capital analyst reading an investor update for a portfolio company.
      Extract structured intelligence from this presentation with the precision of someone who will be
      held accountable for the accuracy of every number and claim at a board meeting.

      Company: #{company_name}
      Period:  #{period_label}

      EXTRACTION RULES:
      - Use exact names, numbers, dates, and verbatim language from the document wherever possible.
      - For commitments, copy the actual phrasing management used — "we will", "we are committed to",
        "we expect", "our target is". The verbatim language signals how firm the commitment was.
      - For risks, capture the exact severity language management used (not your own assessment).
      - For key_metrics, record the exact value as stated — do not round or normalise.
      - Return empty arrays where a category has no evidence. Never fabricate or infer.
      - management_narrative should capture tone: is management confident, hedging, apologetic,
        pivot-framing? Note any language that softens bad news or buries concerns.

      Return a JSON object with these keys:
      - management_narrative: string — 2–4 sentences covering overall tone, framing, and any notable
          language patterns (e.g. heavy use of "we believe", euphemistic phrasing around misses,
          or unusually confident language on forward targets)
      - commitments: [{description (verbatim or close paraphrase), metric?, target_value?, target_date?,
          confidence_language (the exact phrase used: "committed to" / "plan to" / "expect to" / "targeting")}]
      - risks: [{name, severity (high/medium/low — use management's own language, not your assessment),
          mitigation (what specific action was named?), evidence (verbatim quote)}]
      - accomplishments: [{description, metric?, value?, caveat (any qualifier or asterisk on this claim?)}]
      - forward_plans: [{description, timeline?, owner?, specificity (vague/specific — was a date or metric attached?)}]
      - strategic_objectives: [{description, timeframe?}]
      - key_metrics: [{name, value (exact as stated), unit?, period?, direction (up/down/flat vs prior period if mentioned)}]
      - initiatives: [{name, status (in_progress/planned/completed/dropped), completion_percentage?}]

      Return ONLY the JSON object wrapped in ```json ... ``` fences.

      === PRESENTATION TEXT ===
      #{text}
    PROMPT
  end

  # Comparator prompt: given all period records (or a pair), identify only the
  # items that genuinely changed or were dropped — not a re-listing of everything.
  #
  # PRD §4.2 — the five cross-period lenses.
  def build_comparator_prompt(company_name, records_json)
    <<~PROMPT
      You are a senior VC analyst preparing a pre-board accountability brief for #{company_name}.
      Compare these investor presentations (oldest → newest) and identify only items where there is
      genuine evidence of change, disappearance, contradiction, or inconsistency across periods.

      DO NOT re-list items that remained stable across periods.
      DO NOT flag natural progressions (e.g. a risk resolved on schedule).
      DO flag silent drops, vague reframings, missed commitments with no acknowledgement,
      and metrics that deteriorate without explanation.

      For every flag, write a `note` that reads like a briefing point a skeptical board member
      would raise: what was said, what actually happened, and why it matters. Be specific —
      name the periods, cite the numbers, and surface the accountability gap. Aim for 2–4 sentences.

      Return a JSON object with exactly these keys:

      commitment_tracker: array of explicit commitments and forward plans with specific targets that
        a fund manager would hold management accountable for. Cast a wide net — include items where:
        (a) management later reported against the target (even if it was phrased as "targeting" or "plan to"),
        (b) the commitment shows signs of narrowing or slipping within the available window even if the
            deadline is in the future (e.g. a specific amount becomes a range, a specific quarter becomes
            a range of quarters), or
        (c) the commitment was stated in one period and never mentioned again.
        Do NOT require "committed to" language — "we will", "we plan to", "we are targeting", "we expect"
        all count when paired with a specific metric or date.
        Each item:
        {
          commitment: verbatim or close paraphrase of what management promised,
          from_period: period when the commitment was first made,
          status: "met" | "partially_met" | "missed" | "not_mentioned" | "at_risk",
            use "at_risk" when the deadline has not yet passed but the commitment is already narrowing
            or hedging (e.g. amount widened to a range, timeline slipped to a range),
          evidence: direct quote or specific data point from a later period that confirms, contradicts,
                    or hedges the original commitment (or notes the silence if not_mentioned),
          note: 2–4 sentence briefing point — what was promised, what actually happened or is showing,
                what the gap or risk is, and why a board member should probe it. For at_risk items,
                explain specifically how the commitment has softened and what it implies.
        }

      risk_evolution: risks that materially changed status — resolved, dropped without explanation,
        escalated, or newly introduced. Stable, actively managed risks should NOT appear. Each item:
        {
          name: risk name,
          first_period: period when risk first appeared,
          last_period: period when it last appeared (or was resolved/dropped),
          status: "resolved" | "dropped" | "escalated" | "new" | "ongoing",
          note: 2–4 sentence trajectory story — how the risk evolved across periods, what actions
                (if any) were taken, and what the current status implies. For dropped risks,
                explain what makes the disappearance suspicious (no resolution stated, no update given).
        }

      objective_drift: strategic objectives or ICPs that materially shifted between periods without
        explicit acknowledgement of the change. Gradual, stated evolutions are NOT drift. Each item:
        {
          description: concise label for the objective or ICP that shifted,
          change: "added" | "removed" | "reframed",
          from_period: period of the original framing,
          to_period: period where the new framing appeared,
          evidence: specific language from both periods that illustrates the shift,
          note: 2–3 sentence explanation of what changed, how significant the shift is, and
                what it implies about execution or market feedback (e.g. "The Q1 ICP was
                enterprise SaaS 200–1000 employees. By Q4 this had pivoted to PLG mid-market
                50–500 employees with no transition explanation — a significant strategy change
                that suggests the enterprise motion may not have been working.")
        }

      initiative_graveyard: initiatives announced in earlier periods that quietly disappeared —
        no completion announcement, no cancellation, no follow-up. Each item:
        {
          name: initiative name as it appeared in the presentation,
          first_period: period when announced,
          last_seen_period: last period it appeared in any form,
          note: 2–3 sentence explanation of what was announced, how prominently it featured,
                why the disappearance is notable, and what context might explain it
                (e.g. "The partner ecosystem program was highlighted in Q1 with 3 signed LOIs.
                It received no mention in Q3 or Q4. Given the Q4 pivot to PLG, it is unclear
                whether this program was formally deprioritised or simply abandoned without notice.")
        }

      metric_anomalies: key metrics with notable trends — declining trajectory, large unexplained
        swings, or metrics that were reported prominently in early periods but disappeared later.
        Each item:
        {
          metric: metric name (e.g. "NRR", "Burn", "ARR Growth"),
          description: 2–3 sentences with specific numbers across periods — state the values,
                       the direction of change, and why the trend is notable. Reference exact
                       figures (e.g. "NRR declined from 121% (Q1) to 118% (Q3) to 108% (Q4),
                       a 13-point drop over three periods with no management commentary on
                       the deterioration in expansion revenue quality."),
          periods_affected: array of period labels where the anomaly is visible
        }

      Return ONLY the JSON object wrapped in ```json ... ``` fences.

      === PERIOD RECORDS ===
      #{records_json}
    PROMPT
  end

  # Question prompt: produces the pre-board briefing.
  # Every question must name the specific period and evidence item — generic questions
  # that could apply to any company are useless to a GP (PRD §5).
  def build_question_prompt(company_name, records_json, flags_json)
    <<~PROMPT
      You are a seasoned VC board member preparing for a quarterly review with #{company_name} management.
      Generate 8–12 sharp, specific pre-board questions grounded in the actual data from these presentations.

      Your goal is to surface accountability gaps, probe inconsistencies, and push management to explain
      what the presentations alone cannot answer. These questions should make a well-prepared management
      team slightly uncomfortable — not hostile, but precise enough that vague answers will be obvious.

      QUESTION RULES:
      - Every question must cite a specific number, date, quote, or named item from the presentations.
        A question like "How is ARR growth tracking?" is useless. Instead: "ARR growth decelerated from
        7.2% MoM (Q1) to 4.0% MoM (Q4) — what specifically changed in the sales motion, and why didn't
        the Q3 pipeline of $11M convert at the expected rate?"
      - Draw primarily from the cross-period flags — these are the highest-signal accountability gaps.
      - Cover all flag categories that have items: commitment misses, dropped risks, objective drift,
        abandoned initiatives, metric anomalies.
      - For commitment misses: ask what happened to the specific commitment, not just "how is X going".
      - For dropped risks: ask management to explain the resolution (or lack of one) explicitly.
      - For objective drift: ask management to articulate when the decision was made and what triggered it.
      - For metric anomalies: ask management to explain the specific trend with numbers.
      - Include 1–2 forward-looking questions that connect the flags to future risk (e.g. runway given
        burn trajectory, Series B timing given ARR miss).
      - Do NOT generate questions that could apply to any company. Every question must be uniquely
        grounded in this company's specific data.

      Return a JSON array where each element is:
      {
        question: the full question text — written as you would actually ask it at the board meeting,
                  including the specific data point or quote that grounds it,
        category: "commitment" | "risk" | "objective" | "initiative" | "metric" | "governance",
        source_period: the period(s) the question draws from (e.g. "Q1 2025 → Q4 2025"),
        source_evidence: the specific fact, number, or quote that motivated this question
      }

      Return ONLY the JSON array wrapped in ```json ... ``` fences.

      === PERIOD RECORDS ===
      #{records_json}

      === CROSS-PERIOD FLAGS ===
      #{flags_json}
    PROMPT
  end

  # ─── Config Helpers ───────────────────────────────────────────────────────────

  # Reads the presentation_doc_names CSV custom field.
  # Falls back to DEFAULT_DOC_NAMES when the field is blank or not configured.
  # PRD §12.1 — presentation_doc_names config.
  def presentation_doc_names
    csv   = @support_agent.json_fields["presentation_doc_names"].to_s
    names = csv.split(",").map(&:strip).compact_blank
    names.any? ? names : DEFAULT_DOC_NAMES
  end

  # Returns true unless enable_scoring is explicitly set to "No"/"false"/etc.
  # Defaults to enabled so existing agents and new agents without the field work as before.
  def scoring_enabled?
    val = @support_agent.json_fields["enable_scoring"].to_s.strip.downcase
    val.blank? || %w[no false 0 disabled].exclude?(val)
  end

  # Returns true unless enable_questions is explicitly set to "No"/"false"/etc.
  def questions_enabled?
    val = @support_agent.json_fields["enable_questions"].to_s.strip.downcase
    val.blank? || %w[no false 0 disabled].exclude?(val)
  end

  # ─── LLM Response Helpers ─────────────────────────────────────────────────────

  # Unwraps a RubyLLM response to a plain string (mirrors PortfolioScoringAgent).
  def extract_text_content(response)
    return response.to_s unless response.respond_to?(:content)

    content = response.content
    content.is_a?(RubyLLM::Content) ? content.text : content.to_s
  end

  # Extracts the first JSON object from an LLM response string.
  # Tries fenced blocks first (```json ... ```), then bare braces.
  def extract_json_hash(raw)
    match = raw.match(/```json\s*(\{.+?\})\s*```/m) ||
            raw.match(/```\s*(\{.+?\})\s*```/m) ||
            raw.match(/(\{.+\})/m)
    JSON.parse(match[1]) if match
  rescue JSON::ParserError => e
    Rails.logger.warn { "[PresentationAnalystAgent] JSON parse failed (hash): #{e.message}" }
    nil
  end

  # Extracts the first JSON array from an LLM response string.
  def extract_json_array(raw)
    match = raw.match(/```json\s*(\[.+?\])\s*```/m) ||
            raw.match(/```\s*(\[.+?\])\s*```/m) ||
            raw.match(/(\[.+\])/m)
    JSON.parse(match[1]) if match
  rescue JSON::ParserError => e
    Rails.logger.warn { "[PresentationAnalystAgent] JSON parse failed (array): #{e.message}" }
    nil
  end
end
