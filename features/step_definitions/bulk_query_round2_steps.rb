# Steps for the round 2 query-budget scenarios (tmp/query_fixes_round2.md):
#   features/ai/bulk_query_agents.feature           R1 (RTA), R2 (portfolio scoring), R5 (all-FAQs catalog)
#   features/secondaries/bulk_query_secondaries.feature   R3 (allocation complete email)
#   features/misc/bulk_query_approvals.feature      R4 (approval responses list)
# The budgets themselves use the generic steps in query_budget_steps.rb.

# ── R1: RTA reconciliation ────────────────────────────────────────────────────

Then('the RTA folio {string} is matched to its commitment with status {string}') do |folio_number, status|
  folios = (rta_report_json[:scheme_results] || []).flat_map { |sr| sr[:folio_results] || [] }
  folio = folios.find { |f| f[:folio_number] == folio_number }
  expect(folio).to be_present, "No folio result for #{folio_number}: #{folios.inspect}"
  expect(folio[:commitment_id]).to eq(@commitments.first.id)
  expect(folio[:status].to_s).to eq(status)
end

Then('the report has no blocking issue matching {string}') do |text|
  issues = rta_report_json[:issues] || []
  matching = issues.select { |i| i[:severity].to_s == "blocking" && i[:message].to_s.include?(text) }
  expect(matching).to be_empty, "Expected no blocking issue containing '#{text}', got: #{matching.pluck(:message).join('; ')}"
end

# ── R2: portfolio scoring ─────────────────────────────────────────────────────

# One Actual-tagged quarterly KpiReport per quarter; every KPI has a mapping with a denomination so the gathered
# data shows the mapping was read
def create_quarterly_kpi_report(as_of, approved:, unapproved:)
  report = KpiReport.create!(entity: @entity, portfolio_company_id: @portfolio_company.id, period: "Quarter",
                             as_of:, tag_list: "Actual", user: @user)
  statuses = Array.new(approved, :approved) + Array.new(unapproved, :unapproved)
  statuses.each_with_index do |status, idx|
    mapping = InvestorKpiMapping.where(entity_id: @entity.id, investor_id: @portfolio_company.id,
                                       standard_kpi_name: "KPI #{idx}").first_or_initialize
    mapping.update!(reported_kpi_name: "KPI #{idx}", denomination: "thousands")
    FactoryBot.create(:kpi, kpi_report: report, entity: @entity, portfolio_company_id: @portfolio_company.id,
                            name: "KPI #{idx}", value: idx + 1, investor_kpi_mapping: mapping, status:)
  end
end

Given('the portfolio company has {int} Actual quarterly KPI reports, each with {int} approved and {int} unapproved KPI') do |reports, approved, unapproved|
  reports.times { |i| create_quarterly_kpi_report(Date.new(2025, 3, 31) + (i * 3).months, approved:, unapproved:) }
end

Given('the portfolio company has {int} more Actual quarterly KPI report with only unapproved KPIs') do |reports|
  reports.times { |i| create_quarterly_kpi_report(Date.new(2024, 12, 31) - (i * 3).months, approved: 0, unapproved: 3) }
end

Given('there is a portfolio scoring agent for the entity') do
  @support_agent = SupportAgent.create!(entity: @entity, name: "Scoring Agent", agent_type: "PortfolioScoringAgent",
                                        enabled: true, category: "Portfolio")
end

When('the portfolio scoring agent gathers KPI data for the portfolio company') do
  # gather_kpi_data is the agent's private data-gathering step; allocate skips the Trailblazer pipeline so only
  # that step runs, with the agent it would have loaded in initialize_agent
  agent = PortfolioScoringAgent.allocate
  agent.instance_variable_set(:@support_agent, @support_agent)
  @gathered_kpi_data = agent.send(:gather_kpi_data, @portfolio_company)
end

Then('{int} KPI periods are gathered, each with {int} KPIs carrying their denomination') do |periods, kpis|
  expect(@gathered_kpi_data.size).to eq(periods)
  @gathered_kpi_data.each do |period|
    expect(period[:kpis].size).to eq(kpis), "#{period[:as_of]}: #{period[:kpis].inspect}"
    expect(period[:kpis].pluck(:denomination).uniq).to eq(["thousands"])
  end
end

# ── R3: allocation complete email ─────────────────────────────────────────────

Given('every approved offer of the sale is verified') do
  # This sale's allocation verifies only the offers it matched; the budget below is only meaningful with several
  # verified offers - one would pass with or without the preload
  @sale.offers.approved.update_all(verified: true)
  expect(@sale.offers.verified.count).to be > 1
end

When('the allocation complete notification is sent for the sale') do
  @sale.reload.notify_allocation
end

# ── R4: approval responses list ───────────────────────────────────────────────

Given('the investor has responses on the approval for {int} different funds') do |count|
  @response_funds = Array.new(count) do |i|
    FactoryBot.create(:fund, entity: @entity, name: "Response Fund #{i + 1}")
  end
  @response_funds.each do |fund|
    ApprovalResponse.create!(entity: @entity, approval: @approval, investor: @investor, owner: fund,
                             response_entity: @investor.investor_entity, status: "Pending")
  end
end

Then('I should see a quick response for each of the {int} funds') do |count|
  expect(@response_funds.size).to eq(count)
  @response_funds.each { |fund| expect(page).to have_content("Approval Response for #{fund}") }
end

# ── R5: all-FAQs catalog ──────────────────────────────────────────────────────

# Per guide: a public and a signed-in-only entry, created out of display order so the order check means something
Given('published FAQ entries exist for {int} user guides') do |count|
  # Public entries are allowed only on guides readable without a login
  @faq_guide_keys = (GuideCatalog.guide_keys & PublicGuidesController::PUBLIC_GUIDE_IDS).first(count)
  expect(@faq_guide_keys.size).to eq(count)
  @faq_guide_keys.each do |key|
    FaqEntry.create!(guide_key: key, faq_group: "how_to", position: 2, status: "published", audience: "signed_in",
                     question: "Signed-in question for #{key}?", answer: "Signed-in answer.")
    FaqEntry.create!(guide_key: key, faq_group: "how_to", position: 1, status: "published", audience: "public",
                     question: "Public question for #{key}?", answer: "Public answer.")
  end
end

When('the all-FAQs catalog is built') do
  @faq_guides = FaqCatalog.new(audience: "signed_in").guides
end

When('the public all-FAQs catalog is built') do
  @faq_guides = FaqCatalog.new(audience: "public").guides
end

def catalog_questions(key)
  @faq_guides.find { |g| g.key == key }&.items&.map(&:question)
end

Then('the catalog lists the published FAQ entries of those {int} guides in display order') do |count|
  expect(@faq_guide_keys.size).to eq(count)
  @faq_guide_keys.each do |key|
    expect(catalog_questions(key)).to eq(["Public question for #{key}?", "Signed-in question for #{key}?"])
  end
end

Then('the catalog lists only the public FAQ entries of those {int} guides') do |count|
  expect(@faq_guide_keys.size).to eq(count)
  @faq_guide_keys.each { |key| expect(catalog_questions(key)).to eq(["Public question for #{key}?"]) }
end
