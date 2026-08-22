# frozen_string_literal: true

# Demo presentation-analysis reports for the Presentation Analyst Dashboard.
#
# Fabricates SupportAgentReport rows in the exact shape PresentationAnalystAgent
# writes, so the dashboard can be reviewed without paying for real LLM runs.
# No agent is executed and no LLM is called.
#
# Run with:
#   bundle exec rake presentation_analyst:seed          # entity 157
#   bundle exec rake presentation_analyst:seed[123]     # any entity
#   ENTITY_ID=123 bundle exec rails runner db/seeds/presentation_analyst_reports.rb
#
# Idempotent — every row it writes is tagged json_fields["seeded"] = true and
# deleted on the next run, so repeated runs converge on the same data set.
# The match is on the KEY only: a MySQL json column renders `"seeded": true`
# with a space, so a pattern pinning the value after the colon finds nothing.
#
# @see PresentationAnalystPresenter
# @see PresentationAnalystAgent

# Entity to seed. Override with ENTITY_ID=123, or use the rake wrapper:
#   bundle exec rake presentation_analyst:seed[123]
ENTITY_ID = Integer(ENV.fetch("ENTITY_ID", 157))

support_agent = SupportAgent.find_by!(agent_type: "PresentationAnalystAgent", entity_id: ENTITY_ID)

# Deterministic RNG — the same companies land in the same tiers on every run, so
# a reviewer comparing two screenshots is not chasing random churn. A different
# seed value than portfolio_scoring's own 157 so the two dashboards' random
# choices (which companies get a previous run, which are stale, ...) don't
# mirror each other when both are seeded for the same entity.
rng = Random.new(271)

# ---------------------------------------------------------------------------
# Clear previously seeded rows only. Real agent output (no "seeded" key) survives.
# ---------------------------------------------------------------------------
removed = SupportAgentReport
          .where(support_agent: support_agent, owner_type: "Investor")
          .where("json_fields LIKE '%\"seeded\"%'")
          .destroy_all
          .size
puts "Removed #{removed} previously seeded presentation-analysis report(s)"

# ---------------------------------------------------------------------------
# Score dimensions. Weights match PresentationAnalystAgent#compute_scores
# exactly (Commitment 35 / Risk 25 / Coherence 25 / Narrative 15) so a reviewer
# checking the weighted total against the detail panel sees it reconcile.
#
# Unlike the flags below, these dimension scores are jittered around a target
# rather than derived from the fabricated flags — the same simplification the
# scoring dashboard's own seed makes for its five dimensions. The flags exist
# to give the Cross-Period Flags panel real-looking content, not to make the
# arithmetic independently re-derivable from them.
# ---------------------------------------------------------------------------
SCORE_DIMENSIONS = [
  { key: "commitment_score", weight: 0.35 },
  { key: "risk_score",       weight: 0.25 },
  { key: "coherence_score",  weight: 0.25 },
  { key: "narrative_score",  weight: 0.15 }
].freeze

PERIOD_LABELS = %w[Q1-04-25-Actual Q2-07-25-Actual Q3-10-25-Actual Q4-01-26-Actual].freeze

MGMT_NARRATIVES = [
  "Management struck a confident tone, leading with the ARR beat before turning to hiring plans.",
  "The update leaned heavily on forward guidance with limited detail on the current quarter's shortfalls.",
  "Tone was measured and specific — every claim was paired with a number and a named owner.",
  "Framing shifted noticeably toward efficiency and runway extension compared to prior updates."
].freeze

COMMITMENT_POOL = [
  { "description" => "Reach $8M ARR", "metric" => "ARR", "target_value" => "$8M", "confidence_language" => "we are targeting" },
  { "description" => "Launch the partner integration marketplace", "metric" => nil, "target_value" => nil, "confidence_language" => "we plan to" },
  { "description" => "Bring gross margin above 70%", "metric" => "Gross margin", "target_value" => "70%", "confidence_language" => "we expect to" },
  { "description" => "Close the enterprise reference customer", "metric" => nil, "target_value" => nil, "confidence_language" => "we are committed to" },
  { "description" => "Extend runway past 18 months", "metric" => "Runway", "target_value" => "18 months", "confidence_language" => "we will" }
].freeze

RISK_POOL = [
  { "name" => "Customer concentration", "severity" => "medium", "mitigation" => "Diversifying top-10 accounts through the mid-market motion" },
  { "name" => "Data residency compliance", "severity" => "high", "mitigation" => "Legal review in progress" },
  { "name" => "Key-person dependency on the founding CTO", "severity" => "medium", "mitigation" => "Hiring a VP Engineering" },
  { "name" => "Competitive pricing pressure", "severity" => "low", "mitigation" => "Packaging refresh planned for next quarter" }
].freeze

ACCOMPLISHMENT_POOL = [
  { "description" => "Closed the Series A extension", "metric" => "Cash raised", "value" => "$4M" },
  { "description" => "Shipped the v2 onboarding flow", "metric" => nil, "value" => nil },
  { "description" => "Grew net revenue retention", "metric" => "NRR", "value" => "112%" },
  { "description" => "Reduced monthly burn", "metric" => "Burn", "value" => "-14%" }
].freeze

FORWARD_PLAN_POOL = [
  { "description" => "Open the EMEA go-to-market motion", "timeline" => "next two quarters" },
  { "description" => "Hire a VP of Sales", "timeline" => "this quarter" },
  { "description" => "Ship the usage-based pricing tier", "timeline" => "Q3" }
].freeze

OBJECTIVE_POOL = [
  { "description" => "Enterprise mid-market, 200-1000 employees", "timeframe" => "FY26" },
  { "description" => "Product-market fit in two new verticals", "timeframe" => "FY26" },
  { "description" => "PLG self-serve for SMB", "timeframe" => "next 12 months" }
].freeze

METRIC_POOL = [
  { "name" => "ARR", "unit" => "$", "direction" => "up" },
  { "name" => "NRR", "unit" => "%", "direction" => "flat" },
  { "name" => "Burn", "unit" => "$/mo", "direction" => "down" },
  { "name" => "Runway", "unit" => "months", "direction" => "down" }
].freeze

INITIATIVE_POOL = [
  { "name" => "Partner ecosystem program", "status" => "in_progress" },
  { "name" => "Self-serve onboarding", "status" => "completed" },
  { "name" => "International expansion", "status" => "planned" },
  { "name" => "Enterprise SSO", "status" => "in_progress" }
].freeze

# ---------------------------------------------------------------------------
# Cross-period flag pools — one entry per lens item, matching the shape
# PresentationAnalystAgent's comparator prompt produces. Sampled by tier
# severity below so a Watch/At Risk company's flags panel actually looks worse
# than a High Accountability one, rather than being uncorrelated with the score.
# ---------------------------------------------------------------------------
COMMITMENT_TRACKER_POOL = [
  { "commitment" => "Reach $8M ARR by Q4", "from_period" => "Q1-04-25-Actual", "status" => "missed",
    "evidence" => "Q4 reports $6.1M, a 24% shortfall against the stated target.",
    "note" => "Management committed to $8M ARR in Q1 with no caveats. Q4 reports $6.1M with no acknowledgement of the miss — worth asking what changed and whether the Q1 pipeline assumptions held." },
  { "commitment" => "Launch the automation platform within 90 days", "from_period" => "Q2-07-25-Actual", "status" => "not_mentioned",
    "evidence" => "No mention in Q3 or Q4 updates.",
    "note" => "A firm 90-day commitment in Q2 simply disappeared from subsequent updates with no completion note, deferral, or cancellation stated." },
  { "commitment" => "Close 3 enterprise reference customers", "from_period" => "Q1-04-25-Actual", "status" => "partially_met",
    "evidence" => "Two logos closed by Q3, third still in evaluation as of Q4.",
    "note" => "Two of three targeted logos closed on schedule; the third slipped without a revised date being offered." },
  { "commitment" => "Bring gross margin above 70%", "from_period" => "Q2-07-25-Actual", "status" => "at_risk",
    "evidence" => "Margin range widened from a specific 70% target to \"70-75%\" in Q3.",
    "note" => "The target quietly softened from a specific number to a range before the deadline passed — worth probing what's driving the hedge." },
  { "commitment" => "Extend runway past 18 months", "from_period" => "Q1-04-25-Actual", "status" => "met",
    "evidence" => "Q4 reports 19 months of runway at current burn.",
    "note" => "Delivered as stated, with the underlying burn-reduction actions named in each intervening update." }
].freeze

RISK_EVOLUTION_POOL = [
  { "name" => "Data residency compliance", "first_period" => "Q2-07-25-Actual", "last_period" => "Q3-10-25-Actual", "status" => "dropped",
    "note" => "Flagged as high-priority with active legal review in Q2. No mention in Q3 or Q4 — no resolution stated, no update given." },
  { "name" => "Customer concentration", "first_period" => "Q1-04-25-Actual", "last_period" => "Q4-01-26-Actual", "status" => "ongoing",
    "note" => "Carried across three consecutive updates with near-identical mitigation language each time — limited visible progress." },
  { "name" => "Key-person dependency on the founding CTO", "first_period" => "Q3-10-25-Actual", "last_period" => "Q4-01-26-Actual", "status" => "escalated",
    "note" => "Framed as low-severity in Q3; Q4 adds \"actively recruiting a successor\" language, suggesting the risk grew rather than stayed static." },
  { "name" => "Competitive pricing pressure", "first_period" => "Q2-07-25-Actual", "last_period" => "Q4-01-26-Actual", "status" => "resolved",
    "note" => "Named in Q2, addressed via the Q3 packaging refresh, and confirmed stabilised in Q4 with win-rate data." }
].freeze

OBJECTIVE_DRIFT_POOL = [
  { "description" => "Primary ICP", "change" => "reframed", "from_period" => "Q1-04-25-Actual", "to_period" => "Q3-10-25-Actual",
    "evidence" => "Q1: \"enterprise mid-market, 200-1000 employees\". Q3: \"PLG self-serve, 50-500 employees\", no transition explanation.",
    "note" => "A significant ICP pivot with no acknowledgement of the change or what triggered it — worth asking whether the enterprise motion underperformed." },
  { "description" => "Year 2 success definition", "change" => "removed", "from_period" => "Q1-04-25-Actual", "to_period" => "Q3-10-25-Actual",
    "evidence" => "Q1 defined success as \"$12M ARR and 200 enterprise customers\". By Q3 the goal is \"product-market fit in two new verticals\" — a numerical target replaced with a qualitative one.",
    "note" => "Replacing a measurable target with a qualitative one makes the next check-in harder to hold management accountable against." }
].freeze

INITIATIVE_GRAVEYARD_POOL = [
  { "name" => "Partner ecosystem program", "first_period" => "Q1-04-25-Actual", "last_seen_period" => "Q1-04-25-Actual",
    "note" => "Highlighted in Q1 with 3 signed LOIs. No mention in Q2, Q3 or Q4 — unclear whether it was deprioritised or quietly dropped." },
  { "name" => "International expansion", "first_period" => "Q2-07-25-Actual", "last_seen_period" => "Q3-10-25-Actual",
    "note" => "Named as a Q3 priority in the Q2 deck, then absent from the Q4 update with no completion or cancellation note." }
].freeze

METRIC_ANOMALY_POOL = [
  { "metric" => "NRR", "description" => "NRR declined from 121% (Q1) to 118% (Q3) to 108% (Q4), a 13-point drop over three periods with no management commentary on the deterioration.",
    "periods_affected" => %w[Q1-04-25-Actual Q3-10-25-Actual Q4-01-26-Actual] },
  { "metric" => "Burn", "description" => "Q3 states $650K/month burn and 14 months of runway, implying roughly $9.1M cash on hand — difficult to reconcile with the $18M raised and the spend trajectory shown in prior decks.",
    "periods_affected" => %w[Q3-10-25-Actual] }
].freeze

QUESTION_POOL = [
  { "question" => "In Q1 you committed to $8M ARR by Q4. The Q4 deck reports $6.1M — a 24% shortfall against your own target. What is the explanation, and what is the updated guidance?", "category" => "commitment" },
  { "question" => "The Q2 presentation stated the automation platform would launch \"within 90 days\". Q3 and Q4 make no mention of it. Was it launched, deferred, or cancelled?", "category" => "commitment" },
  { "question" => "Data residency compliance was flagged as high-priority in Q2 with active legal review. It does not appear in Q3 or Q4. Was it resolved? If not, why removed from reporting?", "category" => "risk" },
  { "question" => "Customer concentration has been flagged in three consecutive updates with near-identical mitigations. What concrete progress has actually been made?", "category" => "risk" },
  { "question" => "Q1 and Q2 positioned enterprise mid-market as the primary ICP. Q3 pivots to SMB self-serve without referencing the prior focus. Was enterprise abandoned, or is SMB additive?", "category" => "objective" },
  { "question" => "The partner ecosystem program launched with 3 signed LOIs in Q1 and then vanished from every subsequent update. What happened to it?", "category" => "initiative" },
  { "question" => "NRR declined from 121% to 118% to 108% over three periods with no commentary anywhere in the decks. What is the intervention?", "category" => "metric" },
  { "question" => "Given the current burn trajectory and the Q4 runway figure, when do you expect to need to raise again, and what milestones are you targeting before that round?", "category" => "governance" },
  { "question" => "The gross margin target quietly widened from a specific 70% to a 70-75% range before the deadline passed. What's driving the hedge?", "category" => "commitment" },
  { "question" => "Year 2 success was originally defined as \"$12M ARR and 200 enterprise customers\". By Q3 it reads as \"product-market fit in two new verticals\" — why did a numeric target become qualitative?", "category" => "objective" }
].freeze

# Builds one score payload. Dimension scores are generated first and the
# overall score is the weighted sum, matching PresentationAnalystAgent's own
# 35/25/25/15 weighting so the numbers reconcile.
#
# @param target [Integer] the overall score to centre the dimensions on
# @param periods [Integer] periods_analyzed count to embed in the score payload
# @param rng [Random]
# @return [Hash]
def build_presentation_score(target, periods, rng)
  scores = SCORE_DIMENSIONS.to_h do |dim|
    raw = target + rng.rand(-12..12)
    [dim[:key], raw.clamp(0, 100)]
  end

  overall = SCORE_DIMENSIONS.sum { |dim| scores[dim[:key]] * dim[:weight] }.round
  grade = PresentationAnalystPresenter::GRADE_BANDS
          .find { |b| overall.between?(b[:min], b[:max]) }
          .fetch(:grade)

  {
    "overall_score" => overall,
    "grade" => grade,
    "commitment_score" => scores["commitment_score"],
    "risk_score" => scores["risk_score"],
    "coherence_score" => scores["coherence_score"],
    "narrative_score" => scores["narrative_score"],
    "periods_analyzed" => periods
  }
end

# Samples cross-period flags scaled to how the tier should look — a Watch/At
# Risk company gets more items, and worse ones, than a High Accountability one.
# Not mathematically derived from the score above (see the comment on
# SCORE_DIMENSIONS) — this exists to give the Cross-Period Flags panel
# realistic-looking content, not to reconcile arithmetic.
#
# @param tier_slug [String]
# @param rng [Random]
# @return [Hash]
def build_flags(tier_slug, rng)
  density = case tier_slug
            when "high_accountability" then 0..1
            when "reliable"            then 0..2
            when "watch"               then 1..3
            else                            2..4
            end

  {
    "commitment_tracker" => COMMITMENT_TRACKER_POOL.sample(rng.rand(density).clamp(0, COMMITMENT_TRACKER_POOL.size), random: rng),
    "risk_evolution" => RISK_EVOLUTION_POOL.sample(rng.rand(density).clamp(0, RISK_EVOLUTION_POOL.size), random: rng),
    "objective_drift" => OBJECTIVE_DRIFT_POOL.sample(rng.rand(0..[density.end - 1, 0].max).clamp(0, OBJECTIVE_DRIFT_POOL.size), random: rng),
    "initiative_graveyard" => INITIATIVE_GRAVEYARD_POOL.sample(rng.rand(0..[density.end - 1, 0].max).clamp(0, INITIATIVE_GRAVEYARD_POOL.size), random: rng),
    "metric_anomalies" => METRIC_ANOMALY_POOL.sample(rng.rand(0..[density.end - 2, 0].max).clamp(0, METRIC_ANOMALY_POOL.size), random: rng)
  }
end

# Fabricates the per-period extraction records store_results writes to
# "period_records". Nothing in the dashboard renders these directly today —
# they exist so the agent's chat provider and the per-company report tab have
# real-looking source data behind the score and flags.
#
# @param period_count [Integer]
# @param rng [Random]
# @return [Array<Hash>]
def build_period_records(period_count, rng)
  PERIOD_LABELS.last(period_count).map do |label|
    {
      "period_label" => label,
      "as_of" => Date.current.beginning_of_month.iso8601,
      "management_narrative" => MGMT_NARRATIVES.sample(random: rng),
      "commitments" => COMMITMENT_POOL.sample(rng.rand(1..2), random: rng),
      "risks" => RISK_POOL.sample(rng.rand(1..2), random: rng),
      "accomplishments" => ACCOMPLISHMENT_POOL.sample(rng.rand(1..2), random: rng),
      "forward_plans" => FORWARD_PLAN_POOL.sample(1, random: rng),
      "strategic_objectives" => OBJECTIVE_POOL.sample(1, random: rng),
      "key_metrics" => METRIC_POOL.sample(rng.rand(1..2), random: rng).map { |m| m.merge("value" => rng.rand(10..200).to_s, "period" => label) },
      "initiatives" => INITIATIVE_POOL.sample(1, random: rng)
    }
  end
end

# Creates a report row and back-dates it. created_at must be set after insert
# because the timestamp drives both the stale check and the movement ordering,
# and after_create :mark_as_latest! relies on insertion order to pick a
# winner — so rows are always inserted oldest first per company.
#
# @return [SupportAgentReport]
def create_presentation_report!(investor:, support_agent:, json_fields:, status:, created_at:)
  report = SupportAgentReport.create!(
    owner: investor,
    support_agent: support_agent,
    status: status,
    json_fields: json_fields
  )
  report.update_columns(created_at: created_at, updated_at: created_at)
  report
end

# ---------------------------------------------------------------------------
# Pick the companies to analyze. Unlike PortfolioScoringAgent, this agent needs
# no sector — every portfolio company is eligible, so there is no "no sector"
# split to preserve.
# ---------------------------------------------------------------------------
eligible = Investor.where(entity_id: ENTITY_ID)
                   .where("LOWER(category) = ?", "portfolio company")
                   .order(:id)
                   .to_a

puts "#{eligible.size} eligible portfolio companies"

companies = eligible.shuffle(random: rng)

# Reserve a slice that is deliberately left with no report at all, so the
# dashboard's Not Analyzed card has something to show.
#
# No blocked runs are seeded, for the same reason the scoring seed avoids fake
# failures: a fabricated "found nothing to analyze" run is indistinguishable
# from a real one, and sends a reviewer chasing a bug that never happened.
never_run_companies = companies.first(4)
remaining = companies[4..] || []

# One company demonstrates the "scoring deliberately disabled" state — a real,
# deliberately-triggered config state (not a failure), distinct from both a
# blocked run and a normal score.
scoring_disabled_company = remaining.shift
analyzed_companies = remaining

# Target distribution across the analyzed companies — weighted toward the
# middle tiers, the way a real portfolio's management-accountability spread
# tends to sit.
tier_targets = []
tier_targets.concat(Array.new((analyzed_companies.size * 0.2).round) { rng.rand(80..97) })  # High Accountability
tier_targets.concat(Array.new((analyzed_companies.size * 0.45).round) { rng.rand(60..79) }) # Reliable
tier_targets.concat(Array.new((analyzed_companies.size * 0.2).round) { rng.rand(50..59) })  # Watch
# Remainder falls into At Risk so the counts always add up to the company count.
tier_targets.concat(Array.new(analyzed_companies.size - tier_targets.size) { rng.rand(15..49) })
tier_targets = tier_targets.first(analyzed_companies.size).shuffle(random: rng)

# @param target [Integer]
# @return [String] tier slug, for scaling the flag density to match
def tier_for_target(target)
  PresentationAnalystPresenter::TIERS.find { |t| target.between?(t[:min], t[:max]) }&.fetch(:slug) || "at_risk"
end

now = Time.current

created_analyzed = 0
created_previous = 0
stale_marked = 0

analyzed_companies.each_with_index do |investor, index|
  target = tier_targets[index]
  tier_slug = tier_for_target(target)

  # Roughly three quarters of companies get a previous run too, so the
  # movement panel and the table's delta column have something to compare.
  has_previous = index % 4 != 3

  # A handful of companies get a latest run old enough to trip the staleness
  # threshold, so that state is visible on the dashboard.
  is_stale = index % 11 == 5
  latest_at = if is_stale
                now - rng.rand(95..170).days
              else
                now - rng.rand(1..40).days
              end

  periods = rng.rand(2..4)

  if has_previous
    drift = rng.rand(-14..14)
    previous_target = (target - drift).clamp(15, 97)
    previous_at = latest_at - rng.rand(80..130).days
    previous_tier = tier_for_target(previous_target)
    previous_flags = build_flags(previous_tier, rng)

    create_presentation_report!(
      investor: investor,
      support_agent: support_agent,
      status: :completed,
      created_at: previous_at,
      json_fields: {
        "period_records" => build_period_records(periods, rng),
        "cross_period_flags" => previous_flags,
        "analyst_questions" => QUESTION_POOL.sample(rng.rand(4..8), random: rng),
        "periods_analyzed" => PERIOD_LABELS.last(periods),
        "flags_digest" => Digest::SHA256.hexdigest(JSON.generate(previous_flags)),
        "score" => build_presentation_score(previous_target, periods, rng),
        "final_status" => "ready",
        "run_at" => previous_at.iso8601,
        "completed_at" => previous_at.iso8601,
        "scoring_enabled" => true,
        "questions_enabled" => true,
        "seeded" => true
      }
    )
    created_previous += 1
  end

  flags = build_flags(tier_slug, rng)

  create_presentation_report!(
    investor: investor,
    support_agent: support_agent,
    status: :completed,
    created_at: latest_at,
    json_fields: {
      "period_records" => build_period_records(periods, rng),
      "cross_period_flags" => flags,
      "analyst_questions" => QUESTION_POOL.sample(rng.rand(4..8), random: rng),
      "periods_analyzed" => PERIOD_LABELS.last(periods),
      "flags_digest" => Digest::SHA256.hexdigest(JSON.generate(flags)),
      "score" => build_presentation_score(target, periods, rng),
      "final_status" => "ready",
      "run_at" => latest_at.iso8601,
      "completed_at" => latest_at.iso8601,
      "scoring_enabled" => true,
      "questions_enabled" => true,
      "seeded" => true
    }
  )
  created_analyzed += 1
  stale_marked += 1 if is_stale
end

# The scoring-disabled demo company — real flags and questions, no score.
if scoring_disabled_company
  disabled_at = now - rng.rand(1..30).days
  disabled_flags = build_flags("reliable", rng)

  create_presentation_report!(
    investor: scoring_disabled_company,
    support_agent: support_agent,
    status: :completed,
    created_at: disabled_at,
    json_fields: {
      "period_records" => build_period_records(rng.rand(2..3), rng),
      "cross_period_flags" => disabled_flags,
      "analyst_questions" => QUESTION_POOL.sample(rng.rand(4..6), random: rng),
      "periods_analyzed" => PERIOD_LABELS.last(rng.rand(2..3)),
      "flags_digest" => Digest::SHA256.hexdigest(JSON.generate(disabled_flags)),
      "score" => nil,
      "final_status" => "ready",
      "run_at" => disabled_at.iso8601,
      "completed_at" => disabled_at.iso8601,
      "scoring_enabled" => false,
      "questions_enabled" => true,
      "seeded" => true
    }
  )
  puts "  #{scoring_disabled_company.investor_name}: scoring disabled (real flags, no score)"
end

# ---------------------------------------------------------------------------
# Report back using the presenter itself, so the summary printed here is
# exactly what the dashboard will render.
# ---------------------------------------------------------------------------
reports = SupportAgentReport
          .where(support_agent: support_agent, owner_type: "Investor")
          .where(created_at: 12.months.ago..)
          .where("json_fields LIKE '%\"final_status\":%' AND json_fields NOT LIKE '%\"steps\":%'")
          .includes(:owner)
          .order(created_at: :desc)
          .to_a

presenter = PresentationAnalystPresenter.new(reports, support_agent)

puts
puts "Created #{created_analyzed} latest analysis(es), #{created_previous} previous run(s), " \
     "#{never_run_companies.size} left never-run, 1 scoring-disabled"
puts
puts "Dashboard will show:"
PresentationAnalystPresenter::TIERS.each do |tier|
  puts format("  %-22s %3d companies (%s of portfolio)",
              presenter.label_for(tier[:slug]),
              presenter.counts_by_tier[tier[:slug]],
              "#{presenter.share_for_tier(tier[:slug])}%")
end
puts format("  %-22s %3d companies %s", "Not Analyzed", presenter.not_analyzed_count, presenter.not_analyzed_breakdown.inspect)
puts
puts "  Grade distribution: #{presenter.grade_distribution.inspect}"
puts "  Movement: #{presenter.improved_count} improved, #{presenter.declined_count} declined, #{presenter.unchanged_count} unchanged"
puts "  Stale (> #{presenter.staleness_days} days): #{presenter.stale_count}"
puts "  Cross-period flags tally: #{presenter.flags_tally.inspect}"
if presenter.cross_reference_available?
  puts "  Narrative risk (strong fundamentals, weak accountability): #{presenter.narrative_risk_companies.size} companies"
else
  puts "  No PortfolioScoringAgent for this entity — cross-reference callout will be empty. Run" \
       " `bundle exec rake portfolio_scoring:seed[#{ENTITY_ID}]` too if you want to see it."
end
puts
puts "Visit /presentation_analyst_dashboard"
