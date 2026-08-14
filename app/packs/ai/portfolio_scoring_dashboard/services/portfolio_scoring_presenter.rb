# frozen_string_literal: true

# Computes grade-band aggregations from PortfolioScoringAgent reports.
#
# Takes every scoring SupportAgentReport for the agent within the look-back
# window (already loaded by PortfolioScoringDashboardController), groups them
# per company to find each company's latest and previous score, and produces
# the tier counts, grade distribution, and movement figures the dashboard renders.
#
# The central rule: a company's tier is ALWAYS derived from `overall_score`,
# never from the LLM's `grade` string. `overall_score` is validated in
# PortfolioScoringAgent#validate_score_keys! (integer 0-100); `grade` is free
# text written by whichever sector skill file matched and is display-only.
#
# @see PortfolioScoringAgent
# @see PortfolioScoringDashboardController
class PortfolioScoringPresenter
  # Tier definitions — the four buckets the stat cards show, in display order.
  # `slug` is what appears in URLs (?status=watch) so links stay stable even if
  # the grade letters in a sector skill file ever change.
  # `color` is a Bootstrap contextual name, matching _score_display.html.erb's
  # existing thresholds (success / primary / warning / danger).
  TIERS = [
    { slug: "outperform", label: "Outperformers", grades: "A+ / A", min: 80, max: 100, color: "success", icon: "ti-trending-up" },
    { slug: "on_track",   label: "On Track",      grades: "B+ / B", min: 60, max: 79,  color: "primary", icon: "ti-circle-check" },
    { slug: "watch",      label: "Watch List",    grades: "C+ / C", min: 40, max: 59,  color: "warning", icon: "ti-eye" },
    { slug: "at_risk",    label: "At Risk",       grades: "D",      min: 0,  max: 39,  color: "danger",  icon: "ti-alert-triangle" }
  ].freeze

  # The fifth card. Not a score range — a roll-up of the three ways a company
  # can end up with no usable score (see #not_scored_breakdown).
  NOT_SCORED = { slug: "not_scored", label: "Not Scored", grades: nil, color: "secondary", icon: "ti-help-circle" }.freeze

  # The seven grade bands from docs/ai/skills/generic_portfolio_scoring_skill.md.
  # Drives the distribution chart's fixed x-axis; each band maps to a tier so the
  # bar colour is inherited rather than separately defined.
  GRADE_BANDS = [
    { grade: "A+", min: 90, max: 100, tier: "outperform" },
    { grade: "A",  min: 80, max: 89,  tier: "outperform" },
    { grade: "B+", min: 70, max: 79,  tier: "on_track" },
    { grade: "B",  min: 60, max: 69,  tier: "on_track" },
    { grade: "C+", min: 50, max: 59,  tier: "watch" },
    { grade: "C",  min: 40, max: 49,  tier: "watch" },
    { grade: "D",  min: 0,  max: 39,  tier: "at_risk" }
  ].freeze

  # Fallback when the agent has no "score_staleness_days" config field set.
  DEFAULT_STALENESS_DAYS = 90

  attr_reader :support_agent, :basis

  # @param reports [Array<SupportAgentReport>] all scoring reports in the look-back
  #   window, newest first — NOT pre-filtered to latest-per-company. The previous
  #   report per company is needed for the movement figures.
  # @param support_agent [SupportAgent] the PortfolioScoringAgent record
  # @param basis [Symbol] :count to weight tiers by number of companies,
  #   :value to weight them by portfolio FMV
  # @param company_ids [Array<Integer>, nil] restricts the company universe to a
  #   sector/tag subset. nil means the whole portfolio. Every count, percentage
  #   and "not scored" figure is computed against this universe, so a filtered
  #   dashboard describes the subset rather than mixing it with the whole book.
  def initialize(reports, support_agent, basis: :count, company_ids: nil)
    @support_agent = support_agent
    @basis = basis == :value ? :value : :count
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
  # @return [Hash] the tier definition (or NOT_SCORED)
  def tier_meta(slug)
    TIERS.find { |t| t[:slug] == slug.to_s } || NOT_SCORED
  end

  # Every value ?status= may legitimately take.
  # @return [Array<String>]
  def self.filter_slugs
    @filter_slugs ||= (TIERS.pluck(:slug) + [NOT_SCORED[:slug]] + MOVEMENT_FILTERS).freeze
  end

  # The canonical display label — "Watch List (C+ / C)". Generated from the band
  # table so a view can never hand-type a label that drifts from the slug.
  #
  # @param slug [String]
  # @return [String]
  def label_for(slug)
    meta = tier_meta(slug)
    meta[:grades].present? ? "#{meta[:label]} (#{meta[:grades]})" : meta[:label]
  end

  # Filters that cut across tiers rather than being one. These come from the
  # Score Movement panel, where every figure is clickable — a count the FM can
  # see but not open is a dead end.
  MOVEMENT_FILTERS = %w[improved declined unchanged stale].freeze

  # Human label for any ?status= value, tier or movement filter alike, so the
  # table's filter chip always names what is on screen.
  #
  # @param slug [String]
  # @return [String]
  def filter_label(slug)
    case slug.to_s
    when "improved"  then "Improved since last run"
    when "declined"  then "Declined since last run"
    when "unchanged" then "Unchanged since last run"
    when "stale"     then "Scores older than #{staleness_days} days"
    else label_for(slug)
    end
  end

  # Latest reports matching a movement filter. Kept beside the counts so the
  # figure on the panel and the rows in the table can never disagree.
  #
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
  #
  # @param score [Integer, nil] overall_score
  # @return [String, nil] tier slug, or nil when there is no score
  def tier_for(score)
    return nil if score.nil?

    TIERS.find { |t| score.between?(t[:min], t[:max]) }&.fetch(:slug)
  end

  # @param score [Integer, nil]
  # @return [String, nil] the grade band letter the score falls in (NOT the LLM's string)
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

  # Latest reports that carry a usable score payload.
  # @return [Array<SupportAgentReport>]
  def scored_reports
    @scored_reports ||= latest_reports.select { |r| score_for(r).present? }
  end

  # Latest reports where the run happened but produced no score — the agent
  # stored json_fields["error"] instead (no skill file, LLM failure, bad JSON).
  # @return [Array<SupportAgentReport>]
  def failed_reports
    @failed_reports ||= latest_reports - scored_reports
  end

  # Ids of the latest report per company — used by the controller to narrow the
  # table's Ransack scope to one row per company.
  # @return [Array<Integer>]
  def latest_report_ids
    @latest_report_ids ||= latest_reports.map(&:id)
  end

  # --- Company universe ---------------------------------------------------

  # Every portfolio company in the entity, scored or not. The denominator for
  # all the percentages on the cards.
  # @return [Integer]
  def total_companies
    @total_companies ||= portfolio_companies.size
  end

  # Companies that have never produced a scoring report, split by whether the
  # cause is fixable configuration (no sector) or simply an un-run agent.
  # A company with a blank sector never even enters PortfolioScoringAgent#targets.
  #
  # @return [Array<Hash>] { id:, name:, sector:, reason: } sorted by name
  def unscored_companies
    @unscored_companies ||= begin
      reported = @by_owner.keys.to_set
      portfolio_companies.reject { |c| reported.include?(c[:id]) }
                         .map { |c| c.merge(reason: c[:sector].to_s.strip.empty? ? :no_sector : :never_run) }
                         .sort_by { |c| c[:name].to_s.downcase }
    end
  end

  # The three ways a company ends up in the Not Scored card. Kept separate
  # because "no sector" and "no skill file" are configuration the FM can fix,
  # while "never run" just needs the agent run.
  #
  # @return [Hash{Symbol => Integer}]
  def not_scored_breakdown
    @not_scored_breakdown ||= {
      failed: failed_reports.size,
      no_sector: unscored_companies.count { |c| c[:reason] == :no_sector },
      never_run: unscored_companies.count { |c| c[:reason] == :never_run }
    }
  end

  # @return [Integer] total companies with no usable score
  def not_scored_count
    not_scored_breakdown.values.sum
  end

  # --- Tier aggregations --------------------------------------------------

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

  # Portfolio value sitting in each tier, in entity-currency cents.
  # Answers "how much of the book is on the watch list", which a headcount can't.
  #
  # @return [Hash{String => Integer}] tier slug => cents
  def value_by_tier
    @value_by_tier ||= begin
      totals = TIERS.to_h { |t| [t[:slug], 0] }
      scored_reports.each do |report|
        slug = tier_for(score_for(report))
        totals[slug] += fmv_cents_by_company.fetch(report.owner_id, 0) if slug
      end
      totals
    end
  end

  # The value the cards display, switching on the count/value toggle.
  #
  # @param slug [String] tier slug
  # @return [Integer] company count, or cents when basis is :value
  def amount_for_tier(slug)
    basis == :value ? value_by_tier.fetch(slug, 0) : counts_by_tier.fetch(slug, 0)
  end

  # Denominator for the card percentages.
  #
  # Both bases count the WHOLE portfolio, scored or not. Count mode always did
  # (total_companies includes unscored); value mode used to sum only the scored
  # tiers, so the tier shares reached 100% on their own and the Not Scored
  # segment pushed the stacked bar past 100%.
  #
  # @return [Integer]
  def basis_total
    @basis_total ||= basis == :value ? total_portfolio_value_cents : total_companies
  end

  # Entity-currency value of every portfolio company in scope, scored or not.
  # @return [Integer] cents
  def total_portfolio_value_cents
    @total_portfolio_value_cents ||= fmv_cents_by_company.values.sum
  end

  # Value held by companies with no usable score — the remainder of the book.
  # @return [Integer] cents
  def not_scored_value_cents
    total_portfolio_value_cents - value_by_tier.values.sum
  end

  # Share of the portfolio with no usable score, on whichever basis is active,
  # so the stacked bar's segments always add up to 100%.
  #
  # @return [Float]
  def share_for_not_scored
    return 0.0 if basis_total.zero?

    amount = basis == :value ? not_scored_value_cents : not_scored_count
    (amount * 100.0 / basis_total).round(1)
  end

  # @param slug [String] tier slug
  # @return [Float] this tier's share of the portfolio, 0.0 when nothing to divide by
  def share_for_tier(slug)
    return 0.0 if basis_total.zero?

    (amount_for_tier(slug) * 100.0 / basis_total).round(1)
  end

  # Formats a tier amount for display — a plain integer for counts, a rounded
  # Money string for value.
  #
  # @param slug [String] tier slug
  # @return [String]
  def formatted_amount_for_tier(slug)
    return counts_by_tier.fetch(slug, 0).to_s unless basis == :value

    format_cents(value_by_tier.fetch(slug, 0))
  end

  # --- Distribution -------------------------------------------------------

  # Counts across all seven grade bands, zeros included so the chart's x-axis
  # stays fixed run to run.
  #
  # @return [Hash{String => Integer}] grade letter => company count
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

  # Tier slug per band, so a chart bar can link to the right table filter.
  # @return [Array<String>]
  def distribution_tiers
    GRADE_BANDS.pluck(:tier)
  end

  # Chart.js can't read CSS variables, so the tier colours are duplicated here
  # as hex. Values are the Bootstrap 5 contextual colours the rest of the
  # scoring UI already uses.
  # --- Movement -----------------------------------------------------------

  # Score change per company between its latest and previous scoring run.
  # Only companies with two scored reports appear.
  #
  # @return [Array<Hash>] { investor_id:, name:, from:, to:, delta:, from_grade:, to_grade: }
  def movements
    @movements ||= @by_owner.filter_map do |owner_id, reports|
      latest = reports.first
      to = score_for(latest)
      next if to.nil?

      # Skip past any failed runs in between: a [scored, failed, scored] history
      # otherwise produced no delta at all and the company was silently counted
      # as unchanged.
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

  # @return [Integer] companies whose score rose since the previous run
  def improved_count
    @improved_count ||= movements.count { |m| m[:delta].positive? }
  end

  # @return [Integer] companies whose score fell since the previous run
  def declined_count
    @declined_count ||= movements.count { |m| m[:delta].negative? }
  end

  # Scored companies with no change — includes those with only one run, which
  # have nothing to compare against. Derived from the same selector the
  # "unchanged" filter uses, so the panel figure and the filtered table match.
  # @return [Integer]
  def unchanged_count
    @unchanged_count ||= reports_for_movement("unchanged").size
  end

  # The biggest movers in both directions, largest absolute change first.
  #
  # @param limit [Integer] how many rows the panel shows
  # @return [Array<Hash>]
  def movers(limit: 4)
    movements.reject { |m| m[:delta].zero? }
             .sort_by { |m| -m[:delta].abs }
             .first(limit)
  end

  # @return [Integer] days after which a score is considered out of date
  def staleness_days
    @staleness_days ||= begin
      configured = support_agent.json_fields["score_staleness_days"].to_i
      configured.positive? ? configured : DEFAULT_STALENESS_DAYS
    end
  end

  # @return [Integer] scored companies whose newest score predates the staleness window
  def stale_count
    @stale_count ||= scored_reports.count { |r| stale?(r) }
  end

  # @param report [SupportAgentReport]
  # @return [Boolean]
  def stale?(report)
    report.created_at < staleness_days.days.ago
  end

  # @return [Time, nil] when the agent last produced any report
  def last_run_at
    @last_run_at ||= latest_reports.map(&:created_at).max
  end

  # --- Active selection ----------------------------------------------------

  # Reports matching any ?status= value — a tier slug, a movement filter, or
  # not_scored. One place resolves every filter, so the controller's table scope
  # and the hero's selection summary can never disagree about what is selected.
  #
  # @param slug [String, nil]
  # @return [Array<SupportAgentReport>] empty when nothing is filtered
  def reports_for_filter(slug)
    return [] if slug.blank?
    return failed_reports if slug == NOT_SCORED[:slug]
    return reports_for_movement(slug) if MOVEMENT_FILTERS.include?(slug)

    scored_reports.select { |r| tier_for_report(r) == slug }
  end

  # @param reports [Array<SupportAgentReport>]
  # @return [Integer, nil] mean score, nil when none of them carry one
  def average_score_of(reports)
    scores = reports.filter_map { |r| score_for(r) }
    return nil if scores.empty?

    (scores.sum.to_f / scores.size).round
  end

  # @param reports [Array<SupportAgentReport>]
  # @return [Integer] entity-currency cents held by these companies
  def value_cents_of(reports)
    reports.sum { |r| fmv_cents_by_company.fetch(r.owner_id, 0) }
  end

  # Average score movement across a selection, so a filtered hero can still say
  # which way that group is heading.
  #
  # @param reports [Array<SupportAgentReport>]
  # @return [Float, nil] nil when none of them have a previous run
  def average_delta_of(reports)
    deltas = reports.filter_map { |r| delta_for(r) }
    return nil if deltas.empty?

    (deltas.sum.to_f / deltas.size).round(1)
  end

  # --- Headline ------------------------------------------------------------

  # The single number the FM repeats in an IC meeting. Five tier cards make the
  # reader assemble this themselves; stating it is the page's job.
  #
  # Respects the count/value basis: on :value it is FMV-weighted, so one large
  # holding scoring badly moves it more than three small ones scoring well.
  #
  # @return [Integer, nil] 0-100, or nil when nothing is scored
  def headline_score
    return @headline_score if defined?(@headline_score)

    @headline_score = begin
      scores = scored_reports.filter_map { |r| score_for(r) }
      if scores.empty?
        nil
      elsif basis == :value
        weighted = scored_reports.sum { |r| score_for(r).to_i * fmv_cents_by_company.fetch(r.owner_id, 0) }
        total = scored_reports.sum { |r| fmv_cents_by_company.fetch(r.owner_id, 0) }
        # Every company can have zero FMV recorded — fall back to the plain mean
        # rather than dividing by zero and reporting a meaningless 0.
        total.zero? ? (scores.sum.to_f / scores.size).round : (weighted.to_f / total).round
      else
        (scores.sum.to_f / scores.size).round
      end
    end
  end

  # @return [String, nil] the grade band the headline score falls in
  def headline_band
    band_for(headline_score)
  end

  # @return [String, nil] tier slug for the headline score
  def headline_tier
    tier_for(headline_score)
  end

  # Average score change per company, over the companies that have a previous
  # run to compare against. A mean of deltas rather than a difference of means,
  # so it reads literally as "the average company moved this much".
  #
  # @return [Float, nil] nil when no company has been scored twice
  def headline_delta
    return @headline_delta if defined?(@headline_delta)

    @headline_delta = if movements.empty?
                        nil
                      else
                        (movements.sum { |m| m[:delta] }.to_f / movements.size).round(1)
                      end
  end

  # @return [Integer] companies the headline delta is averaged over
  def comparable_count
    movements.size
  end

  # Portfolio value sitting in the two tiers that need action. The sentence that
  # actually gets attention in a value-weighted read of the book.
  #
  # @return [Integer] cents
  def value_needing_attention_cents
    value_by_tier.fetch("watch", 0) + value_by_tier.fetch("at_risk", 0)
  end

  # --- Insights ------------------------------------------------------------

  # Which dimension drags the whole book down. The table shows the weakest
  # dimension per company; nobody aggregates it, yet that aggregate is the
  # portfolio-level finding.
  #
  # @param limit [Integer]
  # @return [Array<Array(String, Integer)>] [[dimension name, company count], ...] desc
  def weakest_dimension_tally(limit: 5)
    @weakest_dimension_tally ||= scored_reports
                                 .filter_map { |r| weakest_dimension_for(r) }
                                 .tally
                                 .sort_by { |name, count| [-count, name] }
    @weakest_dimension_tally.first(limit)
  end

  # Average score per sector, so the sector dropdown becomes analysis rather
  # than just a filter. Sectors with a single company are kept but flagged by
  # their count — a one-company "sector" average is not a trend.
  #
  # @return [Array<Hash>] { sector:, average:, count: } sorted best first
  def sector_averages
    @sector_averages ||= scored_reports
                         .group_by { |r| sector_for(r).presence || "Unspecified" }
                         .map do |sector, reports|
                           scores = reports.filter_map { |r| score_for(r) }
                           { sector: sector,
                             average: (scores.sum.to_f / scores.size).round,
                             count: scores.size }
                         end
                         .sort_by { |row| -row[:average] }
  end

  # Portfolio average score per calendar month across every run in the window —
  # trajectory, not just the last step. Months with no run are omitted rather
  # than plotted as zero, which would read as a collapse.
  #
  # @return [Array<Hash>] { label:, average:, count: } oldest first
  def monthly_score_trend
    @monthly_score_trend ||= all_scored_reports
                             .group_by { |r| r.created_at.beginning_of_month }
                             .sort_by(&:first)
                             .map do |month, reports|
                               scores = reports.filter_map { |r| score_for(r) }
                               { label: month.strftime("%b %y"),
                                 average: (scores.sum.to_f / scores.size).round,
                                 count: scores.size }
                             end
  end

  # A trend needs at least two points to mean anything.
  # @return [Boolean]
  def trend?
    monthly_score_trend.size > 1
  end

  # Every scored report in the window, not just the latest per company — the
  # trend is built from the full history.
  # @return [Array<SupportAgentReport>]
  def all_scored_reports
    @all_scored_reports ||= @by_owner.values.flatten.select { |r| score_for(r).present? }
  end

  # --- Per-row helpers (used by the table) --------------------------------

  # The validated score payload, or nil for a failed run.
  # @param report [SupportAgentReport]
  # @return [Integer, nil]
  def score_for(report)
    payload = score_payload(report)
    return nil if payload.blank?

    value = payload["overall_score"]
    return nil if value.nil?

    value.to_i
  end

  # The LLM's grade string. Display only — never used to bucket. Falls back to
  # the score-derived band when the skill file omitted a grade.
  #
  # @param report [SupportAgentReport]
  # @return [String, nil]
  def grade_for(report)
    payload = score_payload(report)
    return nil if payload.blank?

    payload["grade"].to_s.strip.presence || band_for(score_for(report))
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

  # Change vs this company's previous scored run.
  # @param report [SupportAgentReport]
  # @return [Integer, nil] nil when there is nothing to compare against
  def delta_for(report)
    movements_by_owner[report.owner_id]&.fetch(:delta)
  end

  # Movements indexed by company. delta_for is called once per table row, and a
  # linear scan per call made rendering O(rows x movements).
  # @return [Hash{Integer => Hash}]
  def movements_by_owner
    @movements_by_owner ||= movements.index_by { |m| m[:investor_id] }
  end

  # The dimension the agent scored lowest — the column that turns the table from
  # a leaderboard into a triage list. Free: the data is already in the payload.
  #
  # @param report [SupportAgentReport]
  # @return [String, nil]
  def weakest_dimension_for(report)
    dimensions = Array(score_payload(report)["dimensions"])
    return nil if dimensions.empty?

    dimensions.min_by { |d| d["score"].to_i }["name"]
  end

  # @param report [SupportAgentReport]
  # @return [String] sector recorded at scoring time, falling back to the investor's current sector
  def sector_for(report)
    score_payload(report)["sector"].presence ||
      report.json_fields["sector"].presence ||
      report.owner&.sector
  end

  # @param report [SupportAgentReport]
  # @return [String]
  def company_name(report)
    report.owner&.investor_name.presence || report.owner_name.presence || "Unknown"
  end

  # What the agent actually had to work with when it produced this score. The
  # agent records it in data_coverage; surfacing it stops a confident-looking
  # number built on one KPI period from reading the same as a well-evidenced one.
  #
  # The LLM writes these values as either a scalar (3) or a list (["Q1","Q2"]),
  # so both shapes are normalised to a count here.
  #
  # @param report [SupportAgentReport]
  # @return [Hash] empty when the payload carried no data_coverage
  def coverage_for(report)
    raw = score_payload(report)["data_coverage"]
    return {} unless raw.is_a?(Hash)

    {
      kpi_periods: coverage_count(raw["kpi_periods"]),
      valuations_used: coverage_count(raw["valuations_used"]),
      documents_read: coverage_count(raw["documents_read"])
    }
  end

  # Flags a score the agent produced from very little evidence, so the FM can
  # discount it rather than treating every score as equally grounded.
  #
  # @param report [SupportAgentReport]
  # @return [Boolean]
  def thin_evidence?(report)
    coverage = coverage_for(report)
    return false if coverage.empty?

    coverage[:kpi_periods] <= 1 && coverage[:documents_read].zero?
  end

  # @param report [SupportAgentReport]
  # @return [String, nil] failure reason for a run that produced no score
  def error_for(report)
    report.json_fields["error"].presence
  end

  # @param report [SupportAgentReport]
  # @return [Boolean] whether a human overrode the agent's numbers via the score editor
  def manually_edited?(report)
    report.json_fields["manually_edited"].present?
  end

  # Formats entity-currency cents for display, rounded to whole units — the
  # cards show portfolio scale, not exact amounts.
  #
  # @param cents [Integer]
  # @return [String]
  def format_cents(cents)
    Money.new(cents, entity_currency).format(no_cents: true)
  end

  private

  # data_coverage values arrive as either a count or a list of the things
  # counted — mirrors the same guard in _score_display.html.erb.
  #
  # @param value [Integer, Array, nil]
  # @return [Integer]
  def coverage_count(value)
    value.is_a?(Array) ? value.size : value.to_i
  end

  # The score hash the agent stored. Guards against a report row whose
  # json_fields["score"] is a string or otherwise malformed.
  #
  # @param report [SupportAgentReport]
  # @return [Hash]
  def score_payload(report)
    payload = report.json_fields["score"]
    payload.is_a?(Hash) ? payload : {}
  end

  # Portfolio companies in the entity as plain hashes — the presenter only needs
  # id / name / sector, so the full Investor rows are never instantiated.
  #
  # @return [Array<Hash>]
  def portfolio_companies
    @portfolio_companies ||= begin
      scope = Investor
              .where(entity_id: support_agent.entity_id)
              .where("LOWER(category) = ?", "portfolio company")
      # Narrowed to the sector/tag subset when one is active, so percentages are
      # taken against the filtered universe rather than the whole portfolio.
      scope = scope.where(id: @company_ids) if @company_ids

      scope.pluck(:id, :investor_name, :sector)
           .map { |id, name, sector| { id: id, name: name, sector: sector } }
    end
  end

  # Entity-currency FMV per portfolio company.
  #
  # Two corrections over a naive SUM, both of which produced real overstatement:
  #
  # 1. BUY ROWS ONLY. PortfolioInvestment holds a row per buy AND per sell, and
  #    PortfolioComputations#compute_fmv sets `fmv = buy? ? net_quantity * price
  #    : 0`. So a sell row is always zero, and a fully-exited buy row is zero too
  #    because its net quantity has gone to zero. Summing
  #    COALESCE(NULLIF(fmv, 0), amount) across all rows therefore fell back to
  #    the *invested amount* on both — counting an exited position's original
  #    cost and its sale proceeds as though the company were still held.
  #
  # 2. CURRENCY. entity_currency_fmv_cents is only maintained by
  #    TrackingCurrencyJob, which runs for entities that have tracking currency
  #    enabled. Where it is missing, the fund-currency figure is converted here
  #    instead of being silently read as zero — this book holds both INR and USD
  #    funds, so an unconverted sum would be meaningless.
  #
  # The fallback to net invested (buys minus sells, floored at zero) now applies
  # per COMPANY and only when it has no valuation at all, rather than per row.
  #
  # @return [Hash{Integer => Integer}] investor id => cents in entity currency
  def fmv_cents_by_company
    @fmv_cents_by_company ||= begin
      ids = portfolio_companies.pluck(:id)

      if ids.empty?
        {}
      else
        rows = PortfolioInvestment
               .where(entity_id: support_agent.entity_id, portfolio_company_id: ids)
               .pluck(:portfolio_company_id, :fund_id, :quantity,
                      :entity_currency_fmv_cents, :fmv_cents,
                      :entity_currency_amount_cents, :amount_cents)

        currencies = fund_currencies(rows.pluck(1).uniq)
        fmv = Hash.new(0)
        net_invested = Hash.new(0)

        rows.each do |company_id, fund_id, quantity, ec_fmv, fund_fmv, ec_amount, fund_amount|
          currency = currencies[fund_id]
          buy = quantity.to_f.positive?

          # FMV exists only on buy rows; sells are zero by construction.
          fmv[company_id] += entity_cents(ec_fmv, fund_fmv, currency) if buy

          # Net invested: buys add, sells subtract.
          net_invested[company_id] += (buy ? 1 : -1) * entity_cents(ec_amount, fund_amount, currency)
        end

        ids.index_with do |id|
          value = fmv[id]
          value = [net_invested[id], 0].max if value.zero?
          value.round
        end
      end
    end
  end

  # @param fund_ids [Array<Integer>]
  # @return [Hash{Integer => String}] fund id => ISO currency code
  def fund_currencies(fund_ids)
    @fund_currencies ||= Fund.where(id: fund_ids).pluck(:id, :currency).to_h
  end

  # Prefers the maintained entity-currency column, converts the fund-currency
  # figure when it is absent, and returns zero rather than a wrong number when
  # no exchange rate exists.
  #
  # @return [Float] cents in entity currency
  def entity_cents(entity_value, fund_value, fund_currency)
    return entity_value.to_f unless entity_value.to_f.zero?
    return 0.0 if fund_value.to_f.zero?
    return fund_value.to_f if fund_currency.blank? || fund_currency == entity_currency

    rate = exchange_rate_to_entity(fund_currency)
    return fund_value.to_f * rate if rate

    Rails.logger.warn do
      "[PortfolioScoringPresenter] No #{fund_currency}->#{entity_currency} rate for " + "entity #{support_agent.entity_id}; excluding #{fund_value} from the value view."
    end
    0.0
  end

  # Latest available rate into the entity's currency, memoised per source currency.
  #
  # @param from [String] ISO code
  # @return [BigDecimal, nil]
  def exchange_rate_to_entity(from)
    @exchange_rate_to_entity ||= {}
    return @exchange_rate_to_entity[from] if @exchange_rate_to_entity.key?(from)

    @exchange_rate_to_entity[from] = ExchangeRate
                                     .where(entity_id: support_agent.entity_id, from: from, to: entity_currency)
                                     .order(as_of: :asc)
                                     .last&.rate
  end

  # @return [String] ISO code used to format the value view
  def entity_currency
    @entity_currency ||= support_agent.entity.currency.presence || Money.default_currency.iso_code
  end
end
