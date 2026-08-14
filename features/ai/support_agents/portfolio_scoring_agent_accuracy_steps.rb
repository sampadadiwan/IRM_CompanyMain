# Step definitions for the PortfolioScoringAgent accuracy test.
#
# These steps make LIVE LLM calls (tagged @llm in the feature) — nothing here is
# stubbed. The point is to measure whether the agent scores companies the way the
# bundled rubric says it should, which a double would defeat entirely.
#
# Companies are tracked in @scoring_companies (keyed by name) rather than the shared
# @portfolio_company ivar, because the base "there is an existing portfolio company"
# step repoints @portfolio_company/@investor at whichever company was created last.

# ── Data profiles ────────────────────────────────────────────────────────────
#
# Five quarters of Actual KPIs per company. Values are chosen so each of the five
# rubric dimensions lands mid-band — see the table in the feature file header.
# Amounts are in thousands of USD unless the name says otherwise.

# Quarter end dates, oldest first. The LAST one is the "latest" report and is the
# only one the agent reads documents from (docs_from_last_n_reports defaults to 1).
SCORING_QUARTERS = [
  Date.new(2025, 6, 30),
  Date.new(2025, 9, 30),
  Date.new(2025, 12, 31),
  Date.new(2026, 3, 31),
  Date.new(2026, 6, 30)
].freeze

# KPIs carrying money. These get denomination "thousands" on their mapping, which the
# agent passes through to the prompt — so every monetary value below is in thousands
# of USD, CAC and LTV included. Percentages and counts carry no denomination.
SCORING_MONETARY_KPIS = ["Revenue", "CAC", "LTV", "Cash Balance", "Monthly Burn"].freeze

SCORING_PROFILES = {
  # Top-decile on every dimension: 74% YoY growth, 79% gross margin, 4.4x LTV/CAC,
  # 26 months runway, 0.6x burn multiple, up round, complete reporting history.
  "Apex Analytics" => {
    # Every quarter reported — reporting discipline is "Excellent (80-100)".
    quarters: SCORING_QUARTERS,
    kpis: {
      "Revenue"          => [2100, 2600, 3050, 3400, 3654],
      "Gross Margin %"   => [78, 78, 79, 79, 79],
      "CAC"              => [9.5, 9.3, 9.1, 9.0, 9.0],
      "LTV"              => [36.0, 37.5, 38.8, 39.2, 39.6],
      "Cash Balance"     => [17_400, 16_900, 16_400, 16_000, 15_600],
      "Monthly Burn"     => [640, 620, 610, 600, 600],
      "Headcount"        => [92, 101, 109, 115, 120]
    },
    # Prior round -> current round. Up round; $90M on ~$14.6M ARR is 6.2x, inside
    # the rubric's "SaaS: 4-8x ARR is typical" range.
    valuations: [
      { date: Date.new(2024, 6, 30), amount_cents: 31_000_000_00 },
      { date: Date.new(2026, 6, 30), amount_cents: 90_000_000_00 }
    ],
    narrative: <<~TXT
      Apex Analytics — Q2 2026 Investor Update

      Growth. Revenue reached $3.654M for the quarter, up 74% from $2.100M in the
      same quarter last year. Growth has accelerated in each of the last three
      quarters. Net revenue retention is 128%.

      Customer concentration. Our largest customer represents 8% of revenue, and
      the top five customers together represent 24%. No single logo is material to
      the plan.

      Unit economics. Blended gross margin was 79%. Fully loaded CAC is $9.0K
      against an LTV of $39.6K, an LTV/CAC ratio of 4.4x. CAC payback is 11 months.

      Burn and runway. Monthly net burn is $600K against a cash balance of $15.6M,
      giving 26 months of runway at the current rate. Our burn multiple for the
      trailing twelve months is 0.6x — we added $1.55M of net new ARR for every
      $1.0M burned.

      Valuation. We closed an up round at a $90M post-money valuation in June 2026,
      led by a new outside investor, versus $31M at the prior round. That values the
      business at 6.2x ARR. The position is now carried at a 2.9x MOIC against our
      original entry cost.

      Plan performance. Revenue finished 6% ahead of the board-approved budget for
      the quarter. This is the fifth consecutive quarter reported on time, and each
      submission has included a full budget-versus-actual bridge.
    TXT
  },

  # Solidly mid-band: 21% YoY growth, 47% gross margin, 2.3x LTV/CAC, 14 months
  # runway, 1.4x burn multiple, flat round, one quarter of reporting missed.
  "Meridian Cloud" => {
    # Q3 2025 omitted — "mostly regular, core metrics present" is Good (60-79),
    # not Excellent. The gap is structural, not merely asserted in the narrative.
    quarters: SCORING_QUARTERS - [Date.new(2025, 9, 30)],
    kpis: {
      "Revenue"          => [4000, 4380, 4600, 4840],
      "Gross Margin %"   => [46, 47, 47, 47],
      "CAC"              => [12.4, 12.2, 12.1, 12.0],
      "LTV"              => [26.6, 27.0, 27.3, 27.6],
      "Cash Balance"     => [15_300, 14_400, 13_500, 12_600],
      "Monthly Burn"     => [880, 890, 900, 900],
      "Headcount"        => [198, 203, 207, 210]
    },
    # Flat internal round. $87M on ~$19.4M ARR is 4.5x — "typical" for SaaS.
    valuations: [
      { date: Date.new(2024, 6, 30), amount_cents: 86_000_000_00 },
      { date: Date.new(2026, 6, 30), amount_cents: 87_000_000_00 }
    ],
    narrative: <<~TXT
      Meridian Cloud — Q2 2026 Investor Update

      Growth. Revenue was $4.840M for the quarter, up 21% from $4.000M in the same
      quarter last year. Growth has been steady but has not accelerated. Net revenue
      retention is 104%.

      Customer concentration. Our largest customer represents 19% of revenue. We are
      actively working to dilute this but it has not moved materially in a year.

      Unit economics. Gross margin was 47%, held back by hosting costs we have not
      yet renegotiated. CAC is $12.0K against an LTV of $27.6K, an LTV/CAC ratio of
      2.3x. CAC payback is 21 months.

      Burn and runway. Monthly net burn is $900K against a cash balance of $12.6M,
      giving 14 months of runway. Our trailing-twelve-month burn multiple is 1.4x.

      Valuation. We completed a flat internal round at $87M post-money in June 2026,
      essentially unchanged from the $86M prior round. That is 4.5x ARR. The position
      is carried at a 1.3x MOIC against entry cost.

      Plan performance. Revenue finished 4% below the board-approved budget. Our Q3
      2025 report was not submitted; the metrics for that quarter were never filed.
      We do not currently produce a budget-versus-actual bridge with our submissions.
    TXT
  },

  # Distressed on every dimension: -19% YoY, 17% gross margin, 0.8x LTV/CAC,
  # 4 months runway, 3.2x burn multiple, 58% down round, sparse reporting.
  "Halcyon Systems" => {
    # Only three of five quarters filed — "sparse or missing data across multiple
    # periods" is Poor (0-39) on the reporting dimension.
    quarters: [Date.new(2025, 6, 30), Date.new(2025, 12, 31), Date.new(2026, 6, 30)],
    kpis: {
      "Revenue"          => [3000, 2700, 2430],
      "Gross Margin %"   => [22, 19, 17],
      "CAC"              => [18.5, 20.1, 21.0],
      "LTV"              => [18.9, 17.6, 16.8],
      "Cash Balance"     => [10_100, 7400, 4800],
      "Monthly Burn"     => [1050, 1150, 1200],
      "Headcount"        => [284, 271, 260]
    },
    # 58% down round on ~$9.7M ARR.
    valuations: [
      { date: Date.new(2024, 6, 30), amount_cents: 62_000_000_00 },
      { date: Date.new(2026, 6, 30), amount_cents: 26_000_000_00 }
    ],
    narrative: <<~TXT
      Halcyon Systems — Q2 2026 Investor Update

      Growth. Revenue was $2.430M for the quarter, down 19% from $3.000M in the same
      quarter last year. Revenue has declined in every quarter we have reported.
      Net revenue retention is 81% and gross churn is accelerating.

      Customer concentration. Our largest customer represents 41% of revenue and has
      given notice that it will not renew at the end of the contract term.

      Unit economics. Gross margin has compressed to 17% as we discounted to retain
      accounts. CAC is $21.0K against an LTV of $16.8K — an LTV/CAC ratio of 0.8x,
      meaning we currently lose money on every customer we acquire.

      Burn and runway. Monthly net burn is $1.2M against a cash balance of $4.8M,
      leaving approximately 4 months of runway. Our trailing-twelve-month burn
      multiple is 3.2x. We are in breach of the minimum-cash covenant on our venture
      debt facility and have requested a waiver.

      Valuation. We completed a down round at $26M post-money in June 2026, 58% below
      the $62M prior round. The position is carried at a 0.4x MOIC against entry cost.

      Plan performance. Revenue finished 27% below the board-approved budget. We did
      not file reports for Q3 2025 or Q1 2026. A reduction in force of 24% of staff
      was executed in May 2026 and a further restructuring is under consideration.
    TXT
  }
}.freeze

# ── Helpers ──────────────────────────────────────────────────────────────────

# The scoring agent's own template config — the source of truth for its skill fields,
# the real rubric files that back them, and the production json_fields defaults.
def scoring_agent_template
  SupportAgentsSetupService::SUPPORT_AGENT_FORM_CONFIGS
    .find { |c| c[:tag] == "PortfolioScoringAgent" }
    .fetch(:agent)
end

# Creates the scoring agent with the REAL bundled rubrics uploaded, not the two-line
# stub that "there is a fully configured portfolio scoring agent" uses. The rubric's
# bands are what this test measures against, so the genuine files are required.
# Config defaults are taken from the template too, so the agent behaves exactly as a
# freshly provisioned production agent does (min_points_per_section 5, no KPI filter).
def create_scoring_agent_with_real_rubric(entity)
  agent = SupportAgent.create!(
    entity:      entity,
    name:        "Scoring Agent",
    agent_type:  "PortfolioScoringAgent",
    enabled:     true,
    category:    "Portfolio",
    # Pinned so an entity/ENV default change cannot silently move the model under us.
    llm_model:   "gemini-3-flash-preview",
    json_fields: scoring_agent_template.fetch(:json_fields)
  )

  skill_files = scoring_agent_template.fetch(:skill_files)

  SupportAgentsSetupService.skill_field_templates("PortfolioScoringAgent").each do |tpl|
    fcf = agent.form_type.form_custom_fields.create!(
      name:       tpl[:name],
      label:      tpl[:label],
      field_type: "File",
      position:   tpl[:position],
      meta_data:  tpl[:meta_data]
    )

    # Every templated skill field needs its file, or config_issues flags the agent as
    # unhealthy. All three companies are sector "SaaS", so scoring actually resolves to
    # the "sector: General" fallback — but the Beauty & Skincare field must be uploaded
    # too for the agent to be genuinely well configured.
    upload_real_rubric(agent, fcf, skill_files.fetch(tpl[:name]))
  end

  agent
end

# The document name MUST equal fcf.human_label — that is how skill_for_sector finds it.
def upload_real_rubric(support_agent, fcf, relative_path)
  rubric_path = Rails.root.join(relative_path)
  raise "Bundled rubric missing at #{rubric_path}" unless File.exist?(rubric_path)

  doc = Document.new(
    owner:      support_agent,
    name:       fcf.human_label,
    entity_id:  support_agent.entity_id,
    user_id:    @user&.id,
    send_email: false,
    folder:     support_agent.document_folder
  )
  doc.file = File.open(rubric_path, "rb")
  doc.save!
end

# Builds one portfolio company plus its full data profile: Actual/approved quarterly
# KPIs, two valuations, and a narrative document on the most recent KPI report.
def build_scoring_company(name)
  profile = SCORING_PROFILES.fetch(name)

  # All three share sector "SaaS" so they resolve to the same (General) rubric.
  steps %(Given there is an existing portfolio company "name=#{name};category=Portfolio Company;sector=SaaS")
  company = @investor

  @scoring_companies ||= {}
  @scoring_companies[name] = company

  create_scoring_kpis(company, profile)
  create_scoring_valuations(company, profile)
  attach_scoring_narrative(company, profile)

  company
end

# One Actual-tagged KpiReport per quarter, each carrying every KPI in the profile.
# Kpi#status defaults to :approved, which is what gather_kpi_data filters on.
def create_scoring_kpis(company, profile)
  # gather_kpi_data reads investor_kpi_mapping&.denomination, so mappings must exist.
  mappings = profile[:kpis].keys.index_with do |kpi_name|
    mapping = InvestorKpiMapping.where(
      entity_id:         @entity.id,
      investor_id:       company.id,
      standard_kpi_name: kpi_name
    ).first_or_initialize
    mapping.reported_kpi_name = kpi_name
    # Only monetary KPIs get a denomination — the enum has no percentage/count member,
    # and gather_kpi_data compacts a nil denomination out of the prompt payload.
    mapping.denomination      = "thousands" if SCORING_MONETARY_KPIS.include?(kpi_name)
    mapping.save!
    mapping
  end

  profile[:quarters].each_with_index do |as_of, quarter_index|
    report = KpiReport.find_or_create_by!(
      entity:               @entity,
      portfolio_company_id: company.id,
      period:               "Quarter",
      as_of:                as_of,
      tag_list:             "Actual"
    ) { |r| r.user = @user }

    profile[:kpis].each do |kpi_name, values|
      FactoryBot.create(
        :kpi,
        kpi_report:           report,
        entity:               @entity,
        portfolio_company_id: company.id,
        name:                 kpi_name,
        value:                values[quarter_index].to_f,
        investor_kpi_mapping: mappings[kpi_name],
        status:               :approved
      )
    end
  end
end

# gather_valuation_data orders newest-first, so the LLM sees the current mark before
# the prior round and can read the direction of the move.
def create_scoring_valuations(company, profile)
  instrument = FactoryBot.create(
    :investment_instrument,
    entity:            @entity,
    portfolio_company: company,
    name:              "#{company.investor_name} Preferred",
    currency:          "USD"
  )

  # Valuation#currency is derived, not a column — it reads the instrument's currency,
  # which is why the instrument above is created as USD.
  profile[:valuations].each do |val|
    FactoryBot.create(
      :valuation,
      entity:                @entity,
      owner:                 company,
      investment_instrument: instrument,
      valuation_date:        val[:date],
      valuation_cents:       val[:amount_cents]
    )
  end
end

# The narrative carries runway, burn multiple, concentration and round terms — the
# signals that are not expressible as a single KPI value. It must hang off the LATEST
# Actual report, because docs_from_last_n_reports defaults to 1.
def attach_scoring_narrative(company, profile)
  latest = company.portfolio_kpi_reports.where(tag_list: "Actual").order(as_of: :desc).first
  raise "No Actual KPI report to attach the narrative to for #{company.investor_name}" unless latest

  latest.document_folder
  latest.reload

  Tempfile.create(["investor_update", ".txt"]) do |f|
    f.write(profile[:narrative])
    f.flush

    doc = Document.new(
      owner:      latest,
      owner_type: "KpiReport",
      name:       "Investor Update",
      entity_id:  @entity.id,
      user_id:    @user&.id,
      send_email: false,
      folder:     latest.document_folder
    )
    doc.file = File.open(f.path)
    doc.save!
  end
end

# Latest score payload for a company, as stored by PortfolioScoringAgent#store_score.
def scoring_result_for(name)
  @scoring_results.fetch(name) { raise "No scoring result captured for #{name}" }
end

def scoring_score_for(name)
  scoring_result_for(name).fetch("overall_score").to_i
end

# Maps a raw score onto the dashboard tier using the presenter's own bands, so this
# test and the dashboard can never disagree about where a boundary sits.
def scoring_tier_for(score)
  band = PortfolioScoringPresenter::GRADE_BANDS.find { |b| score.between?(b[:min], b[:max]) }
  raise "Score #{score} falls outside every grade band" unless band

  band[:tier]
end

# ── Given ────────────────────────────────────────────────────────────────────

Given("there is a portfolio scoring agent using the real generic scoring rubric") do
  @support_agent = create_scoring_agent_with_real_rubric(@entity)

  # Guard the setup itself — a silent misconfiguration here would look like an
  # accuracy failure rather than a broken fixture.
  issues = PortfolioScoringAgent.config_issues(@support_agent)
  expect(issues).to be_empty, "Scoring agent is misconfigured before the run: #{issues.join(' ')}"
  expect(@support_agent.skill_for_sector("SaaS")).to be_present,
                                                     "Sector 'SaaS' did not fall back to the General skill file"
end

Given("a strong-performing portfolio company {string}") do |name|
  build_scoring_company(name)
end

Given("an average-performing portfolio company {string}") do |name|
  build_scoring_company(name)
end

Given("a distressed portfolio company {string}") do |name|
  build_scoring_company(name)
end

# ── When ─────────────────────────────────────────────────────────────────────

When("the portfolio scoring agent scores all three companies") do
  @scoring_results = {}

  @scoring_companies.each do |name, company|
    # Real LLM call — no stub. support_agent_report is intentionally omitted so the
    # agent skips mark_step_*/finalize_report and never touches ActionCable.
    PortfolioScoringAgent.call(
      support_agent_id: @support_agent.id,
      target:           company,
      entity_id:        @entity.id,
      user_id:          @user.id
    )

    report = SupportAgentReport.where(owner: company, support_agent: @support_agent)
                               .order(created_at: :desc).first
    expect(report).to be_present, "No SupportAgentReport was created for #{name}"

    if report.failed?
      raise "Scoring failed for #{name}: #{report.json_fields['error']}"
    end

    @scoring_results[name] = report.json_fields.fetch("score")
  end

  # Printed unconditionally so a band failure tells you what the LLM actually said.
  puts "\n#### PortfolioScoringAgent accuracy ####"
  @scoring_results.each do |name, score|
    overall = score["overall_score"].to_i
    puts format("  %-18s overall=%-3d grade=%-3s tier=%s",
                name, overall, score["grade"], scoring_tier_for(overall))
  end
end

# ── Then ─────────────────────────────────────────────────────────────────────

# The primary accuracy signal: relative ranking is robust to a uniform bias in the
# LLM's absolute calibration, which the fixed bands below are not.
Then("the scores should be ordered {string} then {string} then {string} with a gap of at least {int}") do |high, mid, low, gap|
  high_score = scoring_score_for(high)
  mid_score  = scoring_score_for(mid)
  low_score  = scoring_score_for(low)

  expect(high_score - mid_score).to be >= gap,
                                    "Expected #{high} (#{high_score}) to beat #{mid} (#{mid_score}) by at least #{gap} points"
  expect(mid_score - low_score).to be >= gap,
                                   "Expected #{mid} (#{mid_score}) to beat #{low} (#{low_score}) by at least #{gap} points"
end

Then("{string} should score at least {int} and land in the {string} tier") do |name, minimum, tier|
  score = scoring_score_for(name)

  expect(score).to be >= minimum, "Expected #{name} to score at least #{minimum}, got #{score}"
  expect(scoring_tier_for(score)).to eq(tier),
                                     "Expected #{name} (score #{score}) in tier '#{tier}', got '#{scoring_tier_for(score)}'"
end

Then("{string} should score at most {int} and land in the {string} tier") do |name, maximum, tier|
  score = scoring_score_for(name)

  expect(score).to be <= maximum, "Expected #{name} to score at most #{maximum}, got #{score}"
  expect(scoring_tier_for(score)).to eq(tier),
                                     "Expected #{name} (score #{score}) in tier '#{tier}', got '#{scoring_tier_for(score)}'"
end

# The middle company has the least headroom on either side, so its tier is asserted
# only as "not either extreme" — the ordering step above carries the real signal.
Then("{string} should score between {int} and {int} and land in neither the {string} nor the {string} tier") do |name, low, high, excluded_a, excluded_b|
  score = scoring_score_for(name)
  tier  = scoring_tier_for(score)

  expect(score).to be_between(low, high),
                   "Expected #{name} to score between #{low} and #{high}, got #{score}"
  expect(tier).not_to eq(excluded_a), "#{name} (score #{score}) should not be in tier '#{excluded_a}'"
  expect(tier).not_to eq(excluded_b), "#{name} (score #{score}) should not be in tier '#{excluded_b}'"
end

# Structural checks: the payload has to be usable by the dashboard, and the LLM's own
# grade string must agree with the band its overall_score falls in.
Then("every scoring report should be complete and internally consistent") do
  # Read from the agent rather than hardcoded — build_scoring_prompt asks the LLM for
  # this many items, so the assertion tracks whatever the template configures.
  min_points = @support_agent.json_fields["min_points_per_section"].to_i
  min_points = 3 if min_points < 1 # mirrors the agent's own floor

  @scoring_companies.each_key do |name|
    score   = scoring_result_for(name)
    overall = score["overall_score"].to_i

    expect(score["summary"]).to be_present, "#{name}: summary is blank"

    dimensions = score["dimensions"]
    expect(dimensions.size).to eq(5), "#{name}: expected 5 rubric dimensions, got #{dimensions.size}"

    dimensions.each do |dim|
      expect(dim["name"]).to be_present, "#{name}: a dimension has no name"
      expect(dim["score"].to_i).to be_between(0, 100), "#{name}/#{dim['name']}: score out of range"
      expect(dim["positives"].to_a.size).to be >= min_points,
                                            "#{name}/#{dim['name']}: expected #{min_points}+ positives, got #{dim['positives'].to_a.size}"
      expect(dim["concerns"].to_a.size).to be >= min_points,
                                           "#{name}/#{dim['name']}: expected #{min_points}+ concerns, got #{dim['concerns'].to_a.size}"
    end

    # A grade that contradicts the model's own number means the output cannot be
    # trusted even when the number happens to land in the right band. Compared at
    # TIER level rather than exact grade: A+/A both mean outperform, so a one-point
    # slip across the 90 boundary is not a scoring error, whereas "scored 90, graded
    # D" is. The grade must still be one the rubric actually defines.
    grade      = score["grade"].to_s.strip
    grade_band = PortfolioScoringPresenter::GRADE_BANDS.find { |b| b[:grade] == grade }

    expect(grade_band).to be_present,
                          "#{name}: grade '#{grade}' is not one of the rubric's grades " \
                          "(#{PortfolioScoringPresenter::GRADE_BANDS.map { |b| b[:grade] }.join(', ')})"
    expect(grade_band[:tier]).to eq(scoring_tier_for(overall)),
                                 "#{name}: graded '#{grade}' (tier '#{grade_band[:tier]}') but scored #{overall} " \
                                 "(tier '#{scoring_tier_for(overall)}')"
  end
end
