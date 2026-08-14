# frozen_string_literal: true

# Demo scoring reports for the Portfolio Scoring Dashboard (entity 157).
#
# Fabricates SupportAgentReport rows in the exact shape PortfolioScoringAgent
# writes, so the dashboard can be reviewed without paying for real LLM runs.
# No agent is executed and no LLM is called.
#
# Run with:
#   bundle exec rails runner db/seeds/portfolio_scoring_reports_157.rb
#
# Idempotent — every row it writes is tagged json_fields["seeded"] = true and
# deleted on the next run, so repeated runs converge on the same data set.
#
# @see PortfolioScoringPresenter
# @see PortfolioScoringAgent

ENTITY_ID = 157

support_agent = SupportAgent.find_by!(agent_type: "PortfolioScoringAgent", entity_id: ENTITY_ID)

# Deterministic RNG — the same companies land in the same tiers on every run, so
# a reviewer comparing two screenshots is not chasing random churn.
rng = Random.new(157)

# ---------------------------------------------------------------------------
# Clear previously seeded rows only. Real agent output (no "seeded" key) survives.
# ---------------------------------------------------------------------------
removed = SupportAgentReport
          .where(support_agent: support_agent, owner_type: "Investor")
          .where("json_fields LIKE '%\"seeded\":true%'")
          .destroy_all
          .size
puts "Removed #{removed} previously seeded scoring report(s)"

# ---------------------------------------------------------------------------
# Scoring dimensions. Weights sum to 1.0 so the weighted total the detail panel
# computes (_score_display renders "sum of contributions") matches overall_score.
# ---------------------------------------------------------------------------
DIMENSIONS = [
  { name: "Revenue Growth", weight: 0.25 },
  { name: "Profitability & Unit Economics", weight: 0.20 },
  { name: "Cash Runway",                 weight: 0.20 },
  { name: "Market Position",             weight: 0.20 },
  { name: "Reporting Quality",           weight: 0.15 }
].freeze

# Narrative fragments keyed by how well the dimension scored. Enough variation
# that the table's "weakest dimension" column and the expanded panels read like
# real analyst output rather than repeated boilerplate.
POSITIVES = {
  "Revenue Growth" => [
    "ARR grew 38% year over year, ahead of the 30% plan",
    "New-customer bookings up 22% quarter on quarter",
    "Net revenue retention held at 114% across the top 20 accounts",
    "Expansion revenue contributed 41% of net new ARR"
  ],
  "Profitability & Unit Economics" => [
    "Gross margin improved 340bps to 71% on hosting renegotiation",
    "CAC payback shortened from 19 to 14 months",
    "Contribution margin turned positive in the latest quarter",
    "LTV/CAC of 3.4x is above the 3.0x sector benchmark"
  ],
  "Cash Runway" => [
    "18 months of runway at the current burn rate",
    "Operating burn reduced 27% following the Q2 cost programme",
    "Undrawn credit facility of USD 5m provides additional headroom",
    "Cash conversion cycle shortened by 11 days"
  ],
  "Market Position" => [
    "Displaced the incumbent in three of five competitive evaluations",
    "Category share estimated at 12%, up from 9% a year ago",
    "Two design-partner logos converted to multi-year contracts",
    "Analyst coverage now lists the company as a challenger"
  ],
  "Reporting Quality" => [
    "Submitted complete KPI packs for four consecutive quarters",
    "Board minutes and audited financials filed on time",
    "Budget-versus-actual variance commentary provided each period",
    "Valuation refreshed within 45 days of period close"
  ]
}.freeze

CONCERNS = {
  "Revenue Growth" => [
    "Growth decelerated from 46% to 38% over the last three quarters",
    "Pipeline coverage for next quarter sits at 2.1x against a 3.0x target",
    "Top-three customer concentration remains at 34% of revenue",
    "Enterprise sales cycle lengthened to 141 days"
  ],
  "Profitability & Unit Economics" => [
    "EBITDA margin remains negative at -12%",
    "Sales and marketing spend at 58% of revenue is above peer median",
    "Discounting increased average contract value erosion to 9%",
    "Support costs scale linearly with accounts, capping gross margin"
  ],
  "Cash Runway" => [
    "Runway falls below 12 months without the planned bridge round",
    "Monthly burn increased for two consecutive periods",
    "Receivable days extended to 74, tightening working capital",
    "No committed follow-on funding identified in the data provided"
  ],
  "Market Position" => [
    "Two well-funded entrants launched competing products this year",
    "Win rate against the primary competitor fell to 38%",
    "Pricing pressure noted in three renewal negotiations",
    "Geographic concentration leaves the business exposed to one market"
  ],
  "Reporting Quality" => [
    "Latest quarter KPI pack submitted 31 days after the deadline",
    "No valuation on file for the most recent period",
    "Headcount and churn metrics missing from the submitted pack",
    "Management commentary omitted budget-variance explanation"
  ]
}.freeze

RATIONALES = {
  high: "Metrics in this dimension are ahead of plan and consistent across the periods reviewed.",
  mid: "Performance is broadly in line with plan, with identifiable gaps that are being addressed.",
  low: "The data shows material weakness here and it is the primary drag on the overall score."
}.freeze

STRENGTHS = [
  "Consistent quarter-on-quarter revenue expansion across the review period",
  "Disciplined cost control following the Q2 operating review",
  "Experienced management team with prior category exits",
  "Diversified customer base across three verticals",
  "Reporting hygiene is among the strongest in the portfolio"
].freeze

RISKS = [
  "Runway dependent on a follow-on round not yet committed",
  "Revenue concentration in the top three accounts",
  "Competitive intensity increasing with two funded entrants",
  "Gross margin structurally capped by support cost scaling",
  "Key-person dependency on the founding CTO"
].freeze

RECOMMENDATIONS = [
  "Request a monthly cash flow forecast until runway exceeds 15 months",
  "Add a board discussion on customer concentration to the next agenda",
  "Commission an independent valuation ahead of the next reporting cycle",
  "Agree a written KPI submission calendar with management",
  "Review the pricing model against the two new market entrants"
].freeze

# Builds one score payload. Dimension scores are generated first and the overall
# score is the weighted sum of them, so the detail panel's arithmetic reconciles.
#
# @param target [Integer] the overall score to centre the dimensions on
# @param rng [Random]
# @return [Hash] the score payload, matching PortfolioScoringAgent's contract
def build_score(target, rng)
  dimensions = DIMENSIONS.map do |dim|
    # Jitter each dimension around the target, clamped to the valid 0-100 range.
    raw = target + rng.rand(-14..14)
    dim_score = raw.clamp(3, 99)

    band = if dim_score >= 75 then :high
           elsif dim_score >= 50 then :mid
           else :low
           end

    {
      "name" => dim[:name],
      "score" => dim_score,
      "weight" => dim[:weight],
      "rationale" => RATIONALES[band],
      "positives" => POSITIVES[dim[:name]].sample(3, random: rng),
      "concerns" => CONCERNS[dim[:name]].sample(3, random: rng)
    }
  end

  overall = dimensions.sum { |d| d["score"] * d["weight"] }.round
  grade = PortfolioScoringPresenter::GRADE_BANDS
          .find { |b| overall.between?(b[:min], b[:max]) }
          .fetch(:grade)
  weakest = dimensions.min_by { |d| d["score"] }

  {
    "overall_score" => overall,
    "grade" => grade,
    "summary" => "Weighted score of #{overall} across five dimensions. " \
                 "#{weakest['name']} is the weakest area at #{weakest['score']}, " \
                 "while #{dimensions.max_by { |d| d['score'] }['name']} is the strongest. " \
                 "Assessment based on the KPI packs, valuations and documents on file.",
    "dimensions" => dimensions,
    "strengths" => STRENGTHS.sample(3, random: rng),
    "risks" => RISKS.sample(3, random: rng),
    "recommendations" => RECOMMENDATIONS.sample(3, random: rng),
    "data_coverage" => {
      "kpi_periods" => rng.rand(2..6),
      "valuations_used" => rng.rand(1..3),
      "documents_read" => rng.rand(0..4)
    }
  }
end

# Creates a report row and back-dates it. created_at must be set after insert
# because the timestamp drives both the stale check and the movement ordering,
# and after_create :mark_as_latest! relies on insertion order to pick a winner —
# so rows are always inserted oldest first per company.
#
# @return [SupportAgentReport]
def create_report!(investor:, support_agent:, json_fields:, status:, created_at:)
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
# Pick the companies to score. Only companies with a sector are eligible — the
# agent skips the rest, and leaving them alone lets the dashboard's "no sector"
# breakdown show real data.
# ---------------------------------------------------------------------------
scorable = Investor.where(entity_id: ENTITY_ID)
                   .where("LOWER(category) = ?", "portfolio company")
                   .where.not(sector: [nil, ""])
                   .order(:id)
                   .to_a

no_sector_count = Investor.where(entity_id: ENTITY_ID)
                          .where("LOWER(category) = ?", "portfolio company")
                          .where(sector: [nil, ""])
                          .count

puts "#{scorable.size} scorable companies (#{no_sector_count} have no sector and are left unscored)"

companies = scorable.shuffle(random: rng)

# Reserve a slice for the states that are not a successful score, so the
# dashboard's Not Scored card and its breakdown all have something to show.
failed_companies = companies.first(2)
never_run_companies = companies[2, 6] || []
scored_companies = companies[8..] || []

# Target distribution across the scored companies — weighted toward the middle
# tiers, the way a real portfolio sits.
tier_targets = []
tier_targets.concat(Array.new((scored_companies.size * 0.21).round) { rng.rand(80..96) })  # Outperformers
tier_targets.concat(Array.new((scored_companies.size * 0.46).round) { rng.rand(60..79) })  # On Track
tier_targets.concat(Array.new((scored_companies.size * 0.23).round) { rng.rand(40..59) })  # Watch List
# Remainder falls into At Risk so the counts always add up to the company count.
tier_targets.concat(Array.new(scored_companies.size - tier_targets.size) { rng.rand(18..39) })
tier_targets = tier_targets.first(scored_companies.size).shuffle(random: rng)

now = Time.current

created_scored = 0
created_previous = 0
stale_marked = 0

scored_companies.each_with_index do |investor, index|
  target = tier_targets[index]

  # Roughly three quarters of companies get a previous run too, so the movement
  # panel and the table's delta column have something to compare against.
  has_previous = index % 4 != 3

  # A handful of companies get a latest score old enough to trip the staleness
  # threshold, so that state is visible on the dashboard.
  is_stale = index % 11 == 5
  latest_at = if is_stale
                now - rng.rand(95..170).days
              else
                now - rng.rand(1..40).days
              end

  if has_previous
    # The previous score sits either side of the latest one, giving a mix of
    # improvements and declines rather than a uniformly rising book.
    drift = rng.rand(-16..16)
    previous_target = (target - drift).clamp(15, 97)
    previous_at = latest_at - rng.rand(80..130).days

    previous_payload = build_score(previous_target, rng)
    create_report!(
      investor: investor,
      support_agent: support_agent,
      status: :completed,
      created_at: previous_at,
      json_fields: {
        "score" => previous_payload,
        "sector" => investor.sector,
        "final_status" => "ready",
        "run_at" => previous_at.iso8601,
        "completed_at" => previous_at.iso8601,
        "seeded" => true
      }
    )
    created_previous += 1
  end

  payload = build_score(target, rng)

  # One company carries a grade string that does not match the standard scale.
  # This is the case the design turns on: the tier still comes from the score,
  # and the odd grade is displayed as-is rather than driving the bucket.
  extra_fields = {}
  if index.zero?
    payload["grade"] = "Tier 2"
    puts "  #{investor.investor_name}: non-standard grade 'Tier 2' on score #{payload['overall_score']} (buckets by score)"
  end

  # One company is marked as manually edited so the pencil marker is visible.
  if index == 1
    extra_fields["manually_edited"] = true
    extra_fields["edited_at"] = (latest_at + 1.day).iso8601
  end

  create_report!(
    investor: investor,
    support_agent: support_agent,
    status: :completed,
    created_at: latest_at,
    json_fields: {
      "score" => payload,
      "sector" => investor.sector,
      "final_status" => "ready",
      "run_at" => latest_at.iso8601,
      "completed_at" => latest_at.iso8601,
      "seeded" => true
    }.merge(extra_fields)
  )
  created_scored += 1
  stale_marked += 1 if is_stale
end

# ---------------------------------------------------------------------------
# Failed runs — the two error paths a real run hits, written in the same shape
# store_score uses on failure.
# ---------------------------------------------------------------------------
failure_messages = [
  "No skill file configured for sector: %<sector>s. Configuration problems: " \
  "No skill file uploaded for '%<sector>s Scoring Skill'. Upload it on the agent edit page.",
  "Score JSON missing required keys: dimensions"
]

failed_companies.each_with_index do |investor, index|
  failed_at = now - rng.rand(2..15).days
  message = format(failure_messages[index % failure_messages.size], sector: investor.sector)

  create_report!(
    investor: investor,
    support_agent: support_agent,
    status: :failed,
    created_at: failed_at,
    json_fields: {
      "error" => message,
      "sector" => investor.sector,
      "final_status" => "failed",
      "run_at" => failed_at.iso8601,
      "completed_at" => failed_at.iso8601,
      "seeded" => true
    }
  )
end

# ---------------------------------------------------------------------------
# Report back using the presenter itself, so the summary printed here is exactly
# what the dashboard will render.
# ---------------------------------------------------------------------------
reports = SupportAgentReport
          .where(support_agent: support_agent, owner_type: "Investor")
          .where(created_at: 12.months.ago..)
          .where("(json_fields LIKE '%\"score\":%' OR json_fields LIKE '%\"error\":%') AND json_fields NOT LIKE '%\"steps\":%'")
          .includes(:owner)
          .order(created_at: :desc)
          .to_a

presenter = PortfolioScoringPresenter.new(reports, support_agent)

puts
puts "Created #{created_scored} latest score(s), #{created_previous} previous score(s), #{failed_companies.size} failed, #{never_run_companies.size} left never-run"
puts
puts "Dashboard will show:"
PortfolioScoringPresenter::TIERS.each do |tier|
  puts format("  %-22s %3d companies (%s of portfolio)",
              presenter.label_for(tier[:slug]),
              presenter.counts_by_tier[tier[:slug]],
              "#{presenter.share_for_tier(tier[:slug])}%")
end
puts format("  %-22s %3d companies %s", "Not Scored", presenter.not_scored_count, presenter.not_scored_breakdown.inspect)
puts
puts "  Grade distribution: #{presenter.grade_distribution.inspect}"
puts "  Movement: #{presenter.improved_count} improved, #{presenter.declined_count} declined, #{presenter.unchanged_count} unchanged"
puts "  Stale (> #{presenter.staleness_days} days): #{presenter.stale_count}"
puts
puts "Visit /portfolio_scoring_dashboard"
