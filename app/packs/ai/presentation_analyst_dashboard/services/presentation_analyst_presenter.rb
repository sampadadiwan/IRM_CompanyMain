# frozen_string_literal: true

# Computes grade-band aggregations, a portfolio-wide cross-period flag tally,
# and a cross-reference against PortfolioScoringAgent from PresentationAnalystAgent
# reports.
#
# Takes every presentation-analysis SupportAgentReport for the agent within
# the look-back window (already loaded by PresentationAnalystDashboardController),
# groups them per company to find each company's latest and previous run, and
# produces everything the dashboard renders.
#
# Modeled directly on PortfolioScoringPresenter, with two structural
# differences: there is no FMV/value weighting here (a Management
# Accountability Score is not a dollar figure, so there is no count/value
# toggle), and this presenter additionally aggregates flags ACROSS companies
# for the Cross-Period Flags panel, which has no equivalent on the scoring
# dashboard.
#
# A portfolio-wide Pre-Board Briefing (aggregating analyst_questions across
# companies) was tried and cut: without a board-meeting date to filter or sort
# on, it ranked by which company was analyzed most recently rather than by
# urgency, which is misleading dressed up as prioritization. Each company's
# own briefing questions are still visible per-row on the dashboard table and
# in its expanded support_agents/presentation_report_detail panel.
#
# @see PresentationAnalystAgent
# @see PresentationAnalystDashboardController
# @see PortfolioScoringPresenter
class PresentationAnalystPresenter
  # Tier definitions — the four buckets the stat cards show, in display order.
  # Bounds match PresentationAnalystAgent#score_to_grade exactly (A 90-100,
  # B+ 80-89, B 70-79, C+ 60-69, C 50-59, D 0-49) rather than reusing
  # PortfolioScoringPresenter::TIERS, whose bounds belong to a different grade
  # scale (that one has an A+ band and splits D at 40, this one does not).
  TIERS = [
    { slug: "high_accountability", label: "High Accountability", grades: "A / B+", min: 80, max: 100, color: "success", icon: "ti-shield-check" },
    { slug: "reliable",            label: "Reliable",            grades: "B / C+", min: 60, max: 79,  color: "primary", icon: "ti-circle-check" },
    { slug: "watch",               label: "Watch",                grades: "C",      min: 50, max: 59,  color: "warning", icon: "ti-eye" },
    { slug: "at_risk",             label: "At Risk",              grades: "D",      min: 0,  max: 49,  color: "danger",  icon: "ti-alert-triangle" }
  ].freeze

  # The fifth card. Not a score range — a roll-up of the two ways a company
  # can end up with no usable score (see #not_analyzed_breakdown).
  NOT_ANALYZED = { slug: "not_analyzed", label: "Not Analyzed", grades: nil, color: "secondary", icon: "ti-help-circle" }.freeze

  # The six grade bands from PresentationAnalystAgent#score_to_grade. Drives
  # the distribution chart's fixed x-axis; each band maps to a tier so the bar
  # colour is inherited rather than separately defined.
  GRADE_BANDS = [
    { grade: "A",  min: 90, max: 100, tier: "high_accountability" },
    { grade: "B+", min: 80, max: 89,  tier: "high_accountability" },
    { grade: "B",  min: 70, max: 79,  tier: "reliable" },
    { grade: "C+", min: 60, max: 69,  tier: "reliable" },
    { grade: "C",  min: 50, max: 59,  tier: "watch" },
    { grade: "D",  min: 0,  max: 49,  tier: "at_risk" }
  ].freeze

  # The five cross-period comparison lenses PresentationAnalystAgent produces,
  # in the order the Cross-Period Flags panel renders them. `score_dim` names
  # which Management Accountability Score dimension each lens feeds, so the
  # panel can point the FM at the number the flag actually moved.
  LENSES = [
    { key: "commitment_tracker",   label: "Commitment Tracker",   icon: "ti-target",         score_dim: "Commitment · 35%" },
    { key: "risk_evolution",       label: "Risk Evolution",       icon: "ti-alert-triangle",  score_dim: "Risk · 25%" },
    { key: "objective_drift",      label: "Objective Drift",      icon: "ti-compass",         score_dim: "Coherence · 25%" },
    { key: "initiative_graveyard", label: "Initiative Graveyard", icon: "ti-ghost",           score_dim: "Coherence · 25%" },
    { key: "metric_anomalies",     label: "Metric Anomalies",     icon: "ti-chart-line",      score_dim: "Narrative · 15%" }
  ].freeze

  # Fallback when the agent has no "score_staleness_days" config field set.
  # Presentation analysis runs roughly once per reporting period rather than
  # continuously, so a longer default than the scoring dashboard's 90 days
  # would be defensible — kept the same for now so "stale" means the same
  # thing across both dashboards until an FM asks for it to differ.
  DEFAULT_STALENESS_DAYS = 90

  attr_reader :support_agent

  # @param reports [Array<SupportAgentReport>] all presentation-analysis
  #   reports for this agent in the look-back window, newest first — NOT
  #   pre-filtered to latest-per-company. The previous report per company is
  #   needed for the movement figures.
  # @param support_agent [SupportAgent] the PresentationAnalystAgent record
  # @param company_ids [Array<Integer>, nil] restricts the company universe to
  #   a sector/tag subset. nil means the whole portfolio.
  def initialize(reports, support_agent, company_ids: nil)
    @support_agent = support_agent
    @company_ids = company_ids

    # Group every report by company, newest first within each group. One pass
    # gives both "latest" and "previous" without a second query or a window
    # function (test env is SQLite, prod is MySQL — keep it in Ruby).
    @by_owner = reports.reject { |r| r.json_fields.blank? }
                       .group_by(&:owner_id)
                       .transform_values { |rs| rs.sort_by(&:created_at).reverse }
  end

  # --- Tier lookup ---------------------------------------------------------

  # @param slug [String]
  # @return [Hash] the tier definition (or NOT_ANALYZED)
  def tier_meta(slug)
    TIERS.find { |t| t[:slug] == slug.to_s } || NOT_ANALYZED
  end

  # Every value ?status= may legitimately take.
  # @return [Array<String>]
  def self.filter_slugs
    @filter_slugs ||= (TIERS.pluck(:slug) + [NOT_ANALYZED[:slug]] + MOVEMENT_FILTERS).freeze
  end

  # @param slug [String]
  # @return [String]
  def label_for(slug)
    meta = tier_meta(slug)
    meta[:grades].present? ? "#{meta[:label]} (#{meta[:grades]})" : meta[:label]
  end

  # Filters that cut across tiers rather than being one. Mirrors the Score
  # Movement pattern on the scoring dashboard — every figure on the Movement
  # panel is clickable, so the filters it links to have to exist here too.
  MOVEMENT_FILTERS = %w[improved declined unchanged stale].freeze

  # @param slug [String]
  # @return [String]
  def filter_label(slug)
    case slug.to_s
    when "improved"  then "Improved since last run"
    when "declined"  then "Declined since last run"
    when "unchanged" then "Unchanged since last run"
    when "stale"     then "Analysis older than #{staleness_days} days"
    else label_for(slug)
    end
  end

  # @param slug [String] one of MOVEMENT_FILTERS
  # @return [Array<SupportAgentReport>]
  def reports_for_movement(slug)
    case slug.to_s
    when "improved"  then scored_reports.select { |r| delta_for(r)&.positive? }
    when "declined"  then scored_reports.select { |r| delta_for(r)&.negative? }
    when "unchanged" then scored_reports.select { |r| delta_for(r).nil? || delta_for(r).zero? }
    when "stale"     then scored_reports.select { |r| stale?(r) }
    else []
    end
  end

  # The one place a score becomes a bucket.
  # @param score [Integer, nil] overall_score
  # @return [String, nil] tier slug, or nil when there is no score
  def tier_for(score)
    return nil if score.nil?

    TIERS.find { |t| score.between?(t[:min], t[:max]) }&.fetch(:slug)
  end

  # @param score [Integer, nil]
  # @return [String, nil] the grade band letter the score falls in (NOT the payload's grade string)
  def band_for(score)
    return nil if score.nil?

    GRADE_BANDS.find { |b| score.between?(b[:min], b[:max]) }&.fetch(:grade)
  end

  # --- Report sets ---------------------------------------------------------

  # The newest report per company, whatever its outcome.
  # @return [Array<SupportAgentReport>]
  def latest_reports
    @latest_reports ||= @by_owner.values.map(&:first)
  end

  # Latest reports that carry a usable score. Deliberately narrower than
  # "has a score payload" — see #score_for for why a blocked run's default
  # arithmetic score cannot be trusted even though the key is present.
  # @return [Array<SupportAgentReport>]
  def scored_reports
    @scored_reports ||= latest_reports.select { |r| score_for(r).present? }
  end

  # Latest reports that ran but produced nothing usable — no presentations
  # matched, or extraction produced zero period records. store_results always
  # sets final_status: "blocked" for these.
  #
  # Excludes reports where scoring was deliberately turned off
  # (enable_scoring: "No") — those have no score for a config reason, not a
  # failure reason, and store_results stamps "scoring_enabled" => false on
  # them precisely so the UI can tell the two apart rather than reading a
  # disabled setting as a failed run.
  # @return [Array<SupportAgentReport>]
  def failed_reports
    @failed_reports ||= (latest_reports - scored_reports).reject { |r| scoring_disabled?(r) }
  end

  # Latest reports with no score because scoring was deliberately disabled on
  # this agent, not because the run failed. Not counted in
  # #not_analyzed_breakdown or any tier — this dashboard has nothing tier-like
  # to say about a company nobody asked to be scored.
  # @return [Array<SupportAgentReport>]
  def scoring_disabled_reports
    @scoring_disabled_reports ||= latest_reports.select { |r| scoring_disabled?(r) && score_for(r).nil? }
  end

  # @param report [SupportAgentReport]
  # @return [Boolean]
  def scoring_disabled?(report)
    report.json_fields["scoring_enabled"] == false
  end

  # @return [Array<Integer>]
  def latest_report_ids
    @latest_report_ids ||= latest_reports.map(&:id)
  end

  # --- Company universe -----------------------------------------------------

  # @return [Integer]
  def total_companies
    @total_companies ||= portfolio_companies.size
  end

  # Companies with no presentation-analysis report at all.
  # @return [Array<Hash>] { id:, name:, sector: } sorted by name
  def unanalyzed_companies
    @unanalyzed_companies ||= begin
      reported = @by_owner.keys.to_set
      portfolio_companies.reject { |c| reported.include?(c[:id]) }
                         .sort_by { |c| c[:name].to_s.downcase }
    end
  end

  # The two ways a company ends up in the Not Analyzed card: it ran but found
  # nothing usable (blocked), or it has never been run at all.
  # @return [Hash{Symbol => Integer}]
  def not_analyzed_breakdown
    @not_analyzed_breakdown ||= { blocked: failed_reports.size, never_run: unanalyzed_companies.size }
  end

  # @return [Integer]
  def not_analyzed_count
    not_analyzed_breakdown.values.sum
  end

  # --- Tier aggregations -----------------------------------------------------

  # @return [Hash{String => Integer}] tier slug => company count (all four keys present)
  def counts_by_tier
    @counts_by_tier ||= begin
      counts = TIERS.to_h { |t| [t[:slug], 0] }
      scored_reports.each do |report|
        slug = tier_for(score_for(report))
        counts[slug] += 1 if slug
      end
      counts
    end
  end

  # @return [Hash{String => Integer}] grade letter => company count, zeros included
  def grade_distribution
    @grade_distribution ||= begin
      counts = GRADE_BANDS.to_h { |b| [b[:grade], 0] }
      scored_reports.each do |report|
        band = band_for(score_for(report))
        counts[band] += 1 if band
      end
      counts
    end
  end

  # @return [Array<String>] tier slug per band, so a chart bar can link to the right table filter
  def distribution_tiers
    GRADE_BANDS.pluck(:tier)
  end

  # Share of the portfolio in a tier, as a percentage of every portfolio
  # company (scored or not) — the denominator that makes the stacked bar on
  # the headline add up to 100% including the Not Analyzed segment.
  # @param slug [String] tier slug
  # @return [Float]
  def share_for_tier(slug)
    return 0.0 if total_companies.zero?

    (counts_by_tier.fetch(slug, 0) * 100.0 / total_companies).round(1)
  end

  # @return [Float]
  def share_for_not_analyzed
    return 0.0 if total_companies.zero?

    (not_analyzed_count * 100.0 / total_companies).round(1)
  end

  # --- Movement --------------------------------------------------------------

  # Score change per company between its latest and previous run. Only
  # companies with two scored reports appear.
  # @return [Array<Hash>] { investor_id:, name:, from:, to:, delta:, from_grade:, to_grade: }
  def movements
    @movements ||= @by_owner.filter_map do |owner_id, reports|
      latest = reports.first
      to = score_for(latest)
      next if to.nil?

      # Skip past any blocked runs in between, same reasoning as the scoring
      # dashboard: a [scored, blocked, scored] history should still produce a
      # delta rather than reading as unchanged.
      previous = reports.drop(1).find { |r| score_for(r) }
      next if previous.nil?

      from = score_for(previous)

      {
        investor_id: owner_id,
        name: company_name(latest),
        from: from,
        to: to,
        delta: to - from,
        from_grade: grade_for(previous),
        to_grade: grade_for(latest)
      }
    end
  end

  # @return [Integer]
  def improved_count
    @improved_count ||= movements.count { |m| m[:delta].positive? }
  end

  # @return [Integer]
  def declined_count
    @declined_count ||= movements.count { |m| m[:delta].negative? }
  end

  # @return [Integer]
  def unchanged_count
    @unchanged_count ||= reports_for_movement("unchanged").size
  end

  # @param limit [Integer]
  # @return [Array<Hash>]
  def movers(limit: 4)
    movements.reject { |m| m[:delta].zero? }
             .sort_by { |m| -m[:delta].abs }
             .first(limit)
  end

  # @return [Integer]
  def staleness_days
    @staleness_days ||= begin
      configured = support_agent.json_fields["score_staleness_days"].to_i
      configured.positive? ? configured : DEFAULT_STALENESS_DAYS
    end
  end

  # @return [Integer]
  def stale_count
    @stale_count ||= scored_reports.count { |r| stale?(r) }
  end

  # @param report [SupportAgentReport]
  # @return [Boolean]
  def stale?(report)
    report.created_at < staleness_days.days.ago
  end

  # @return [Time, nil]
  def last_run_at
    @last_run_at ||= latest_reports.map(&:created_at).max
  end

  # --- Active selection ------------------------------------------------------

  # @param slug [String, nil]
  # @return [Array<SupportAgentReport>] empty when nothing is filtered
  def reports_for_filter(slug)
    return [] if slug.blank?
    return failed_reports if slug == NOT_ANALYZED[:slug]
    return reports_for_movement(slug) if MOVEMENT_FILTERS.include?(slug)

    scored_reports.select { |r| tier_for_report(r) == slug }
  end

  # @param reports [Array<SupportAgentReport>]
  # @return [Integer, nil]
  def average_score_of(reports)
    scores = reports.filter_map { |r| score_for(r) }
    return nil if scores.empty?

    (scores.sum.to_f / scores.size).round
  end

  # @param reports [Array<SupportAgentReport>]
  # @return [Float, nil]
  def average_delta_of(reports)
    deltas = reports.filter_map { |r| delta_for(r) }
    return nil if deltas.empty?

    (deltas.sum.to_f / deltas.size).round(1)
  end

  # --- Headline ----------------------------------------------------------

  # The single number the FM repeats before a board week. Plain mean across
  # scored companies — there is no FMV-weighted variant, unlike the scoring
  # dashboard's headline, because a Management Accountability Score describes
  # communication behaviour, not portfolio value.
  # @return [Integer, nil] 0-100, or nil when nothing is scored
  def headline_score
    return @headline_score if defined?(@headline_score)

    @headline_score = begin
      scores = scored_reports.filter_map { |r| score_for(r) }
      scores.empty? ? nil : (scores.sum.to_f / scores.size).round
    end
  end

  # @return [String, nil]
  def headline_band
    band_for(headline_score)
  end

  # @return [String, nil]
  def headline_tier
    tier_for(headline_score)
  end

  # @return [Float, nil] nil when no company has been analyzed twice
  def headline_delta
    return @headline_delta if defined?(@headline_delta)

    @headline_delta = movements.empty? ? nil : (movements.sum { |m| m[:delta] }.to_f / movements.size).round(1)
  end

  # @return [Integer]
  def comparable_count
    movements.size
  end

  # Companies whose accountability tier needs a board conversation — the
  # sentence that actually gets attention in a pre-board prep session.
  # @return [Integer]
  def companies_needing_followup_count
    counts_by_tier.fetch("watch", 0) + counts_by_tier.fetch("at_risk", 0)
  end

  # --- Cross-Period Flags (portfolio-wide) ------------------------------

  # Latest reports that actually ran extraction and comparison, whether or not
  # they carry a score — scored reports plus scoring-disabled ones. Both
  # produce real cross_period_flags/analyst_questions; only a blocked run (no
  # presentations found, or nothing extracted) has neither. The two
  # portfolio-wide aggregations below read from this set rather than
  # #scored_reports, or a company with scoring turned off would have its real
  # flags and questions silently dropped from the FM's board-prep view even
  # though its own row still shows them.
  # @return [Array<SupportAgentReport>]
  def analyzed_reports
    @analyzed_reports ||= scored_reports + scoring_disabled_reports
  end

  # Tally of flag items across every company's LATEST analysis, one count per
  # lens. This is the portfolio-level finding the per-company report never
  # shows on its own — one company's dropped risk is a footnote, a portfolio
  # tally of dropped risks is a pattern.
  # @return [Hash{String => Integer}] lens key => item count
  def flags_tally
    @flags_tally ||= LENSES.to_h do |lens|
      count = analyzed_reports.sum { |r| Array(cross_period_flags_for(r)[lens[:key]]).size }
      [lens[:key], count]
    end
  end

  # How many distinct companies have at least one item in a given lens — the
  # denominator that turns a raw item count into "how much of the portfolio".
  # @param lens_key [String]
  # @return [Integer]
  def companies_for_lens(lens_key)
    analyzed_reports.count { |r| Array(cross_period_flags_for(r)[lens_key]).any? }
  end

  # Every item in a lens across the whole portfolio, each tagged with the
  # company it came from, most recently analyzed company first.
  # @param lens_key [String]
  # @param limit [Integer, nil]
  # @return [Array<Hash>] { item:, investor_id:, investor_name: }
  def flag_items_for_lens(lens_key, limit: nil)
    items = analyzed_reports.sort_by(&:created_at).reverse.flat_map do |report|
      Array(cross_period_flags_for(report)[lens_key]).map do |item|
        { item: item, investor_id: report.owner_id, investor_name: company_name(report) }
      end
    end
    limit ? items.first(limit) : items
  end

  # --- Cross-reference against PortfolioScoringAgent ----------------------

  # The two scores answer different questions — see docs/ai/investor_presentation_analyst_prd.md
  # §6 — and are designed to be read together. A company that scores well on
  # fundamentals but poorly on accountability is a red flag hidden by looking
  # at either dashboard alone: strong numbers today sitting on top of a
  # pattern of broken commitments and quietly shifted objectives suggests the
  # reporting itself may not be trustworthy going forward.
  #
  # @return [Boolean] whether a PortfolioScoringAgent is configured for this
  #   entity at all — the callout has nothing to show without it
  def cross_reference_available?
    scoring_agent.present?
  end

  # One row per company with both a fundamentals tier and an accountability
  # tier on file.
  # @return [Array<Hash>] { investor_id:, name:, fundamentals_tier:, fundamentals_score:, accountability_tier:, accountability_score:, flag: }
  def cross_reference_rows
    @cross_reference_rows ||= begin
      return [] unless cross_reference_available?

      scoring = fundamentals_scores_by_owner
      scored_reports.filter_map do |report|
        fundamentals_score = scoring[report.owner_id]
        next if fundamentals_score.nil?

        accountability_score = score_for(report)
        fundamentals_tier = PortfolioScoringPresenter::TIERS.find { |t| fundamentals_score.between?(t[:min], t[:max]) }&.fetch(:slug)
        accountability_tier = tier_for(accountability_score)

        {
          investor_id: report.owner_id,
          name: company_name(report),
          fundamentals_tier: fundamentals_tier,
          fundamentals_score: fundamentals_score,
          accountability_tier: accountability_tier,
          accountability_score: accountability_score,
          flag: cross_reference_flag(fundamentals_tier, accountability_tier)
        }
      end
    end
  end

  # Strong fundamentals paired with weak accountability — the direction worth
  # a callout, because it is invisible on either dashboard alone.
  # @return [Array<Hash>]
  def narrative_risk_companies
    cross_reference_rows.select { |r| r[:flag] == :narrative_risk }
  end

  # The mirror case: weak fundamentals, but management is being consistent
  # and honest about it. A different, lower-urgency engagement than a company
  # that looks fine on paper while the story keeps changing underneath.
  # @return [Array<Hash>]
  def honest_underperformer_companies
    cross_reference_rows.select { |r| r[:flag] == :honest_underperformer }
  end

  # --- Per-row helpers (used by the table) --------------------------------

  # The validated score, or nil when the run produced nothing usable.
  #
  # Deliberately checks final_status rather than trusting the presence of a
  # score payload: compute_scores' arithmetic returns neutral-to-generous
  # defaults (50/100/100/100, weighting out to roughly "B+") when every input
  # array is empty — which is exactly what happens on a run that found zero
  # presentations. Without this guard, a company nobody has ever analyzed
  # would appear on the dashboard as a well-scored B+ company.
  #
  # @param report [SupportAgentReport]
  # @return [Integer, nil]
  def score_for(report)
    return nil if report.json_fields["final_status"] == "blocked"

    payload = score_payload(report)
    return nil if payload.blank?

    value = payload["overall_score"]
    value.nil? ? nil : value.to_i
  end

  # @param report [SupportAgentReport]
  # @return [String, nil]
  def grade_for(report)
    return nil if score_for(report).nil?

    score_payload(report)["grade"].to_s.strip.presence || band_for(score_for(report))
  end

  # @param report [SupportAgentReport]
  # @return [String, nil] tier slug
  def tier_for_report(report)
    tier_for(score_for(report))
  end

  # @param report [SupportAgentReport]
  # @return [String] Bootstrap contextual colour for this report's tier
  def color_for_report(report)
    tier_meta(tier_for_report(report).to_s)[:color]
  end

  # @param report [SupportAgentReport]
  # @return [Integer, nil]
  def delta_for(report)
    movements_by_owner[report.owner_id]&.fetch(:delta)
  end

  # @return [Hash{Integer => Hash}]
  def movements_by_owner
    @movements_by_owner ||= movements.index_by { |m| m[:investor_id] }
  end

  # @param report [SupportAgentReport]
  # @return [Array<String>] period labels the run covered
  def periods_analyzed_for(report)
    Array(report.json_fields["periods_analyzed"])
  end

  # @param report [SupportAgentReport]
  # @return [Integer] total items across all five lenses for this company's latest run
  def flags_count_for(report)
    cross_period_flags_for(report).values.sum { |v| Array(v).size }
  end

  # @param report [SupportAgentReport]
  # @return [Integer]
  def questions_count_for(report)
    Array(report.json_fields["analyst_questions"]).size
  end

  # @param report [SupportAgentReport]
  # @return [String]
  def company_name(report)
    report.owner&.investor_name.presence || report.owner_name.presence || "Unknown"
  end

  # @param report [SupportAgentReport]
  # @return [String, nil] sector, read from the investor rather than the
  #   payload — unlike PortfolioScoringAgent, this agent's extraction prompt
  #   never records sector, so there is no scored-at-time value to prefer.
  def sector_for(report)
    report.owner&.sector
  end

  # @param report [SupportAgentReport]
  # @return [String, nil] the reason no score exists, for a blocked run
  def error_for(report)
    return nil unless report.json_fields["final_status"] == "blocked"

    Array(report.json_fields["collection_issues"]).reverse
                                                  .find { |i| i["severity"] == "blocking" }
                                                  &.fetch("message", nil) ||
      Array(report.json_fields["analysis_issues"]).reverse
                                                   .find { |i| i["severity"] == "blocking" }
                                                   &.fetch("message", nil)
  end

  # @param report [SupportAgentReport]
  # @return [Boolean]
  def blocked?(report)
    report.json_fields["final_status"] == "blocked"
  end

  private

  # @param report [SupportAgentReport]
  # @return [Hash] this company's latest cross_period_flags, empty when absent
  def cross_period_flags_for(report)
    raw = report.json_fields["cross_period_flags"]
    raw.is_a?(Hash) ? raw : {}
  end

  # @param fundamentals_tier [String, nil]
  # @param accountability_tier [String, nil]
  # @return [Symbol, nil]
  def cross_reference_flag(fundamentals_tier, accountability_tier)
    strong_fundamentals = %w[outperform on_track].include?(fundamentals_tier)
    weak_fundamentals    = %w[watch at_risk].include?(fundamentals_tier)
    strong_accountability = accountability_tier == "high_accountability"
    weak_accountability    = %w[watch at_risk].include?(accountability_tier)

    return :narrative_risk if strong_fundamentals && weak_accountability
    return :honest_underperformer if weak_fundamentals && strong_accountability

    nil
  end

  # The PortfolioScoringAgent configured for the same entity, if any.
  # @return [SupportAgent, nil]
  def scoring_agent
    return @scoring_agent if defined?(@scoring_agent)

    @scoring_agent = SupportAgent.find_by(agent_type: "PortfolioScoringAgent", entity_id: support_agent.entity_id)
  end

  # Latest PortfolioScoringAgent overall_score per company, scoped to the
  # companies this presenter already knows about (this agent's analyzed
  # universe) rather than the whole portfolio — the cross-reference only ever
  # needs scores for companies that also have an accountability score.
  #
  # Mirrors PortfolioScoringDashboardController#scoring_reports_scope's
  # predicate for isolating real scoring rows from step-tracking rows, and
  # the same LOOK_BACK window, so "latest" means the same thing on both
  # dashboards.
  #
  # @return [Hash{Integer => Integer}] investor id => overall_score
  def fundamentals_scores_by_owner
    @fundamentals_scores_by_owner ||= begin
      ids = @by_owner.keys
      return {} if ids.empty?

      rows = SupportAgentReport
             .where(support_agent: scoring_agent, owner_type: "Investor", owner_id: ids)
             .where(created_at: 12.months.ago..)
             .where(
               "(json_fields LIKE '%\"score\":%' OR json_fields LIKE '%\"error\":%') " \
               "AND json_fields NOT LIKE '%\"steps\":%'"
             )
             .order(created_at: :desc)
             .pluck(:owner_id, :json_fields)

      rows.group_by(&:first).filter_map do |owner_id, group|
        payload = group.first.last["score"]
        next unless payload.is_a?(Hash) && payload["overall_score"]

        [owner_id, payload["overall_score"].to_i]
      end.to_h
    end
  end

  # @param report [SupportAgentReport]
  # @return [Hash] this company's latest score payload, empty when absent
  def score_payload(report)
    payload = report.json_fields["score"]
    payload.is_a?(Hash) ? payload : {}
  end

  # Portfolio companies in the entity as plain hashes.
  # @return [Array<Hash>]
  def portfolio_companies
    @portfolio_companies ||= begin
      scope = Investor
              .where(entity_id: support_agent.entity_id)
              .where("LOWER(category) = ?", "portfolio company")
      scope = scope.where(id: @company_ids) if @company_ids

      scope.pluck(:id, :investor_name, :sector)
           .map { |id, name, sector| { id: id, name: name, sector: sector } }
    end
  end
end
