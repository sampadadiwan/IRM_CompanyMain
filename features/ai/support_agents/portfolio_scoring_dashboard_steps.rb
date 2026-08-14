# Step definitions for the Portfolio Scoring Dashboard.
#
# Reports are built directly rather than by running the agent — the dashboard is
# a read model over SupportAgentReport, so fabricating the payload in the shape
# store_score writes is both faster and keeps the LLM out of the test.

# Builds a score payload matching PortfolioScoringAgent's contract. Dimension
# scores are set to the overall so the detail panel's weighted total reconciles.
#
# @param score [Integer] overall_score
# @param grade [String] the LLM's free-text grade — display only, never bucketed on
# @return [Hash]
def scoring_payload(score, grade)
  {
    "overall_score" => score,
    "grade" => grade,
    "summary" => "Seeded score of #{score}.",
    "dimensions" => [
      { "name" => "Revenue Growth", "score" => score, "weight" => 0.5,
        "rationale" => "Seeded.", "positives" => ["Up"], "concerns" => ["Slowing"] },
      { "name" => "Cash Runway", "score" => score, "weight" => 0.5,
        "rationale" => "Seeded.", "positives" => ["Funded"], "concerns" => ["Burn"] }
    ],
    "strengths" => ["Seeded strength"],
    "risks" => ["Seeded risk"],
    "recommendations" => ["Seeded recommendation"],
    "data_coverage" => { "kpi_periods" => 2, "valuations_used" => 1, "documents_read" => 1 }
  }
end

# Creates a portfolio company for the logged-in entity.
#
# @param name [String]
# @param sector [String, nil] blank means the agent skips it entirely
# @return [Investor]
def create_scoring_portfolio_company(name, sector: "SaaS")
  investor_entity = FactoryBot.create(:entity, name: name)
  FactoryBot.create(:investor,
                    investor_entity: investor_entity,
                    investor_name: name,
                    entity: @entity,
                    category: "Portfolio Company",
                    sector: sector,
                    primary_email: "contact@#{name.parameterize}.com")
end

# Writes one scoring report and back-dates it. created_at drives both the
# staleness check and the latest/previous ordering, so it is set explicitly.
#
# @return [SupportAgentReport]
def create_scoring_report(investor, score:, grade:, created_at: Time.current)
  report = SupportAgentReport.create!(
    owner: investor,
    support_agent: @support_agent,
    status: :completed,
    json_fields: {
      "score" => scoring_payload(score, grade),
      "sector" => investor.sector,
      "final_status" => "ready",
      "run_at" => created_at.iso8601,
      "completed_at" => created_at.iso8601
    }
  )
  report.update_columns(created_at: created_at, updated_at: created_at)
  report
end

# Scopes assertions to the Score Movement card without depending on its position.
def within_movement_panel(&)
  within(:xpath, "//h6[contains(., 'Score Movement')]/ancestor::div[contains(@class, 'card')][1]", &)
end

Given("there is a portfolio scoring agent for the dashboard") do
  @support_agent = FactoryBot.create(:support_agent,
                                     name: "Scoring Agent",
                                     agent_type: "PortfolioScoringAgent",
                                     entity: @entity,
                                     enabled: true)
end

Given("a scored portfolio company {string} with score {int} and grade {string}") do |name, score, grade|
  investor = create_scoring_portfolio_company(name)
  create_scoring_report(investor, score: score, grade: grade)
end

Given("a scored portfolio company {string} in sector {string} with score {int}") do |name, sector, score|
  investor = create_scoring_portfolio_company(name, sector: sector)
  create_scoring_report(investor, score: score, grade: "B")
end

Given("a scored portfolio company {string} tagged {string} with score {int}") do |name, tag, score|
  investor = create_scoring_portfolio_company(name)
  investor.update!(tag_list: tag)
  create_scoring_report(investor, score: score, grade: "B")
end

Given("a portfolio company {string} with no sector") do |name|
  # No sector means PortfolioScoringAgent#targets never selects it, so no report
  # is ever written — the dashboard must account for it separately.
  create_scoring_portfolio_company(name, sector: nil)
end

Given("a failed scoring run for portfolio company {string}") do |name|
  investor = create_scoring_portfolio_company(name)
  SupportAgentReport.create!(
    owner: investor,
    support_agent: @support_agent,
    status: :failed,
    json_fields: {
      "error" => "No skill file configured for sector: #{investor.sector}",
      "sector" => investor.sector,
      "final_status" => "failed",
      "run_at" => Time.current.iso8601,
      "completed_at" => Time.current.iso8601
    }
  )
end

Given("a portfolio company {string} scored {int} three months ago and {int} now") do |name, before, after|
  investor = create_scoring_portfolio_company(name)
  # Oldest first — after_create :mark_as_latest! resolves the winner by insertion order.
  create_scoring_report(investor, score: before, grade: "C+", created_at: 3.months.ago)
  create_scoring_report(investor, score: after, grade: "B+", created_at: Time.current)
end

Given("I am logged in as a user from a different entity") do
  other_entity = FactoryBot.create(:entity, name: "Other Fund")
  @user = FactoryBot.create(:user, entity: other_entity, password: "password")
  @user.add_role(:company_admin)

  # Clear the existing session first: visiting /users/sign_in while still signed
  # in just redirects to the dashboard, so there would be no form to fill.
  Capybara.reset_sessions!

  # Reuse the app's own login steps rather than re-implementing the form.
  steps %(
    Given I am at the login page
    When I fill and submit the login page
  )
end

When("I visit the portfolio scoring dashboard") do
  visit portfolio_scoring_dashboard_path
end

When("I visit the portfolio scoring dashboard filtered by {string}") do |tier|
  visit portfolio_scoring_dashboard_path(status: tier)
end

When("I visit the portfolio scoring dashboard scoped to sector {string}") do |sector|
  visit portfolio_scoring_dashboard_path(sector: sector)
end

When("I visit the portfolio scoring dashboard scoped to tag {string}") do |tag|
  visit portfolio_scoring_dashboard_path(tag: tag)
end

When("I try to visit the portfolio scoring dashboard") do
  # A missing agent for the entity raises RecordNotFound, which the driver may
  # surface as an exception or as an error page depending on config — capture both.
  @access_error = nil
  begin
    visit portfolio_scoring_dashboard_path
  rescue StandardError => e
    @access_error = e
  end
end

Then("the {string} tier should show {int} company") do |tier, count|
  # Scope to the tier's own card rather than searching the page, so another
  # element showing the same number can't make this pass.
  card = find("a.scoring-tier-card[href*='status=#{tier}']", match: :first)
  actual = card.find(".sd-tier-num").text.strip
  expect(actual).to eq(count.to_s), "expected the #{tier} card to show #{count}, got '#{actual}'"
end

Then("the {string} tier should show {int} companies") do |tier, count|
  step %(the "#{tier}" tier should show #{count} company)
end

Then("I should see the filter chip {string}") do |label|
  within("#scoring_table_frame") { expect(page).to have_content(label) }
end

Then("the {string} movement figure should not be a link") do |slug|
  # A zero figure has no rows behind it, so it must render as plain text rather
  # than a link that leads to an empty table.
  expect(page).to have_no_css("a[href*='status=#{slug}']")
end

Then("I should see the scope banner for {string}") do |description|
  expect(page).to have_content(description)
  expect(page).to have_content("Every figure below covers this subset only")
end

Then("the tier card links should keep the sector scope {string}") do |sector|
  PortfolioScoringPresenter::TIERS.each do |tier|
    card = find("a.scoring-tier-card[href*='status=#{tier[:slug]}']", match: :first)
    expect(CGI.unescape(card[:href])).to include("sector=#{sector}"),
                                         "expected the #{tier[:slug]} card to keep sector=#{sector}, got #{card[:href]}"
  end
end

Then("I should see the grade {string} for {string}") do |grade, company|
  row = find("tr", text: company, match: :first)
  expect(row).to have_content(grade)
end

Then("I should see the tier label {string}") do |label|
  expect(page).to have_content(label)
end

Then("I should see {string} in the scoring table") do |company|
  within("#scoring_table_frame") { expect(page).to have_content(company) }
end

Then("I should not see {string} in the scoring table") do |company|
  within("#scoring_table_frame") { expect(page).to have_no_content(company) }
end

Then("the tier card links should use slug {string}") do |slug|
  expect(page).to have_css("a.scoring-tier-card[href*='status=#{slug}']")
  # Grade letters must never appear in a filter URL — they are display only.
  expect(page).to have_no_css("a.scoring-tier-card[href*='status=C']")
  expect(page).to have_no_css("a.scoring-tier-card[href*='status=B']")
end

Then("the not-scored breakdown should show {int} failed and {int} without a sector") do |failed, no_sector|
  card = find("a.scoring-tier-card[href*='status=not_scored']", match: :first)
  expect(card).to have_content("#{failed} failed")
  expect(card).to have_content("#{no_sector} no sector")
end

Then("I should see {string} listed as never scored") do |company|
  # Card headings are uppercased via CSS text-transform and the driver reports
  # rendered text, so match case-insensitively instead of baking in the styling.
  expect(page).to have_content(/never scored/i)
  row = find("tr", text: company, match: :first)
  expect(row).to have_content("No sector set").or have_content("Never run")
end

# Reads one movement tile's figure. Each tile is `<b>N</b><span>label</span>`,
# rendered as a link when it has rows behind it and a plain div when it is zero,
# so this matches on the label text rather than the element type.
def movement_figure(label)
  within_movement_panel do
    find(:xpath, ".//*[contains(@class, 'sd-move')][.//span[normalize-space()='#{label}']]//b").text.strip
  end
end

Then("the movement panel should show {int} improved") do |count|
  expect(movement_figure("improved")).to eq(count.to_s)
end

Then("the movement panel should show {int} improved and {int} declined") do |improved, declined|
  expect(movement_figure("improved")).to eq(improved.to_s)
  expect(movement_figure("declined")).to eq(declined.to_s)
end

Then("the value toggle link should keep the {string} filter") do |tier|
  toggle = find("a", text: "By value", match: :first)
  expect(toggle[:href]).to include("status=#{tier}")
  expect(toggle[:href]).to include("basis=value")
end

Then("I should be denied access to the scoring dashboard") do
  denied = @access_error.is_a?(ActiveRecord::RecordNotFound) ||
           page.has_content?("not found") ||
           page.has_no_content?("Portfolio Scoring Dashboard")
  expect(denied).to be(true), "expected the dashboard to be unreachable from another entity"
end
