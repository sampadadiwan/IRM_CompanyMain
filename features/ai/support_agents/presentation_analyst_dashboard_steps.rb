# Step definitions for the Presentation Analyst Dashboard.
#
# Reports are built directly rather than by running the agent — the dashboard is
# a read model over SupportAgentReport, so fabricating the payload in the shape
# store_results writes is both faster and keeps the LLM out of the test. Several
# generic Then steps from portfolio_scoring_dashboard_steps.rb (tier counts, tier
# labels, "grade for company", movement panel figures) are reused verbatim here —
# this dashboard deliberately shares their markup (scoring-tier-card, sd-tier-num,
# sd-move, the "Score Movement" heading) so they apply to either dashboard's page
# without redefinition. Only phrasing unique to this dashboard is defined below.

# Builds a score payload matching PresentationAnalystAgent's contract.
#
# @param score [Integer] overall_score
# @param grade [String] the agent's free-text grade — display only, never bucketed on
# @return [Hash]
def presentation_score_payload(score, grade)
  {
    "overall_score" => score,
    "grade" => grade,
    "commitment_score" => score,
    "risk_score" => score,
    "coherence_score" => score,
    "narrative_score" => score,
    "periods_analyzed" => 2
  }
end

# @param name [String]
# @param sector [String] presentation analysis needs no sector, unlike scoring —
#   kept configurable only so the sector-scoping scenarios can still exercise it
# @return [Investor]
def create_presentation_portfolio_company(name, sector: "SaaS")
  investor_entity = FactoryBot.create(:entity, name: name)
  FactoryBot.create(:investor,
                    investor_entity: investor_entity,
                    investor_name: name,
                    entity: @entity,
                    category: "Portfolio Company",
                    sector: sector,
                    primary_email: "contact@#{name.parameterize}.com")
end

# Writes one presentation-analysis report and back-dates it. created_at drives
# both the staleness check and the latest/previous ordering.
#
# @return [SupportAgentReport]
def create_presentation_report(investor, score:, grade:, created_at: Time.current,
                               cross_period_flags: {}, analyst_questions: [])
  report = SupportAgentReport.create!(
    owner: investor,
    support_agent: @support_agent,
    status: :completed,
    json_fields: {
      "score" => presentation_score_payload(score, grade),
      "cross_period_flags" => cross_period_flags,
      "analyst_questions" => analyst_questions,
      "periods_analyzed" => ["Q1-Actual", "Q2-Actual"],
      "final_status" => "ready",
      "run_at" => created_at.iso8601,
      "completed_at" => created_at.iso8601
    }
  )
  report.update_columns(created_at: created_at, updated_at: created_at)
  report
end

# A run that found no presentations. compute_scores still runs its
# neutral-to-generous arithmetic (~83, "B+") even with zero evidence — this
# fixture reproduces that exact payload shape so the dashboard's guard against
# trusting a blocked run's score has something real to fail against.
#
# @return [SupportAgentReport]
def create_blocked_presentation_report(investor)
  SupportAgentReport.create!(
    owner: investor,
    support_agent: @support_agent,
    status: :failed,
    json_fields: {
      "score" => presentation_score_payload(83, "B+"),
      "cross_period_flags" => {},
      "analyst_questions" => [],
      "periods_analyzed" => [],
      "collection_issues" => [
        { "type" => "info", "message" => "No presentation documents found matching: Investor Update", "severity" => "blocking" }
      ],
      "final_status" => "blocked",
      "run_at" => Time.current.iso8601,
      "completed_at" => Time.current.iso8601
    }
  )
end

Given("there is a presentation analyst agent for the dashboard") do
  @support_agent = FactoryBot.create(:support_agent,
                                     name: "Presentation Analyst",
                                     agent_type: "PresentationAnalystAgent",
                                     entity: @entity,
                                     enabled: true)
end

Given("there is also a portfolio scoring agent for the dashboard") do
  @scoring_agent = FactoryBot.create(:support_agent,
                                     name: "Scoring Agent",
                                     agent_type: "PortfolioScoringAgent",
                                     entity: @entity,
                                     enabled: true)
end

Given("an analyzed portfolio company {string} with score {int} and grade {string}") do |name, score, grade|
  investor = create_presentation_portfolio_company(name)
  create_presentation_report(investor, score: score, grade: grade)
end

Given("a blocked presentation run for portfolio company {string}") do |name|
  investor = create_presentation_portfolio_company(name)
  create_blocked_presentation_report(investor)
end

Given("a portfolio company {string} that has never been analyzed") do |name|
  create_presentation_portfolio_company(name)
end

Given("a portfolio company {string} analyzed {int} three months ago and {int} now") do |name, before, after|
  investor = create_presentation_portfolio_company(name)
  create_presentation_report(investor, score: before, grade: "C+", created_at: 3.months.ago)
  create_presentation_report(investor, score: after, grade: "B+", created_at: Time.current)
end

Given("an analyzed portfolio company {string} with score {int} and a dropped risk {string}") do |name, score, risk_name|
  investor = create_presentation_portfolio_company(name)
  create_presentation_report(investor, score: score, grade: "B",
                             cross_period_flags: {
                               "risk_evolution" => [
                                 { "name" => risk_name, "status" => "dropped",
                                   "first_period" => "Q1-Actual", "last_period" => "Q2-Actual",
                                   "note" => "Seeded dropped risk for the cross-period flags panel." }
                               ]
                             })
end

Given("{string} also has a fundamentals score of {int}") do |name, score|
  investor = Investor.find_by!(investor_name: name, entity: @entity)
  SupportAgentReport.create!(
    owner: investor,
    support_agent: @scoring_agent,
    status: :completed,
    json_fields: {
      "score" => { "overall_score" => score, "grade" => "A", "dimensions" => [] },
      "final_status" => "ready",
      "run_at" => Time.current.iso8601,
      "completed_at" => Time.current.iso8601
    }
  )
end

# A run that succeeded but with the agent's enable_scoring field set to "No".
# store_results still writes real cross_period_flags/analyst_questions and
# final_status "ready" — only ctx[:score] is nil, stamped with
# scoring_enabled: false so the dashboard can tell "opted out" apart from
# "failed" instead of reading a disabled setting as a failure.
def create_scoring_disabled_report(investor, cross_period_flags: {}, analyst_questions: [])
  SupportAgentReport.create!(
    owner: investor,
    support_agent: @support_agent,
    status: :completed,
    json_fields: {
      "score" => nil,
      "scoring_enabled" => false,
      "questions_enabled" => true,
      "cross_period_flags" => cross_period_flags,
      "analyst_questions" => analyst_questions,
      "periods_analyzed" => ["Q1-Actual", "Q2-Actual"],
      "final_status" => "ready",
      "run_at" => Time.current.iso8601,
      "completed_at" => Time.current.iso8601
    }
  )
end

Given("a portfolio company {string} analyzed with scoring disabled") do |name|
  investor = create_presentation_portfolio_company(name)
  create_scoring_disabled_report(investor)
end

Given("a portfolio company {string} analyzed with scoring disabled and a dropped risk {string}") do |name, risk_name|
  investor = create_presentation_portfolio_company(name)
  create_scoring_disabled_report(investor,
                                 cross_period_flags: {
                                   "risk_evolution" => [
                                     { "name" => risk_name, "status" => "dropped",
                                       "first_period" => "Q1-Actual", "last_period" => "Q2-Actual",
                                       "note" => "Seeded dropped risk on a scoring-disabled company." }
                                   ]
                                 })
end

When("I visit the presentation analyst dashboard") do
  visit presentation_analyst_dashboard_path
end

When("I visit the presentation analyst dashboard filtered by {string}") do |tier|
  visit presentation_analyst_dashboard_path(status: tier)
end

When("I try to visit the presentation analyst dashboard") do
  @access_error = nil
  begin
    visit presentation_analyst_dashboard_path
  rescue StandardError => e
    @access_error = e
  end
end

Then("I should see {string} in the presentation table") do |company|
  within("#presentation_table_frame") { expect(page).to have_content(company) }
end

Then("I should not see {string} in the presentation table") do |company|
  within("#presentation_table_frame") { expect(page).to have_no_content(company) }
end

Then("the not-analyzed breakdown should show {int} blocked and {int} never run") do |blocked, never_run|
  card = find("a.scoring-tier-card[href*='status=not_analyzed']", match: :first)
  # _stats.html.erb collapses to "Every company analyzed" when both counts are zero, and
  # even otherwise only renders a sub-count's text when it's positive (see presenter's
  # not_analyzed_breakdown) — a literal "0 found nothing"/"0 never run" is never rendered.
  if blocked.zero? && never_run.zero?
    expect(card).to have_content("Every company analyzed")
  else
    expect(card).to have_content("#{blocked} found nothing") if blocked.positive?
    expect(card).to have_content("#{never_run} never run") if never_run.positive?
  end
end

Then("I should see {string} listed as never analyzed") do |company|
  expect(page).to have_content(/never analyzed/i)
  row = find("tr", text: company, match: :first)
  expect(row).to have_content(company)
end

# Scopes to one lens card by its label, matching this dashboard's Cross-Period
# Flags panel markup: a bordered card with the lens label in a <small> and the
# item count in the following <h4 class="sd-tier-num">.
def within_lens_card(label, &)
  within(:xpath, "//small[normalize-space()='#{label}']/ancestor::div[contains(@class, 'border')][1]", &)
end

Then("the {string} lens should show {int} item") do |label, count|
  actual = within_lens_card(label) { find(".sd-tier-num").text.strip }
  expect(actual).to eq(count.to_s), "expected the #{label} lens to show #{count}, got '#{actual}'"
end

Then("the {string} lens should show {int} items") do |label, count|
  step %(the "#{label}" lens should show #{count} item)
end

Then("I should see the narrative risk callout for {string}") do |company|
  expect(page).to have_css(".alert-danger", text: company)
end

Then("I should not see the narrative risk callout for {string}") do |company|
  expect(page).to have_no_css(".alert-danger", text: company)
end

Then("I should be denied access to the presentation analyst dashboard") do
  denied = @access_error.is_a?(ActiveRecord::RecordNotFound) ||
           page.has_content?("not found") ||
           page.has_no_content?("Presentation Analyst Dashboard")
  expect(denied).to be(true), "expected the dashboard to be unreachable from another entity"
end

Then("I should see {string} marked as scoring disabled in the presentation table") do |company|
  within("#presentation_table_frame") do
    row = find("tr", text: company, match: :first)
    expect(row).to have_content("Scoring Disabled")
  end
end

# The modal starts hidden (Bootstrap's "fade" class, no "show") — visible:
# :all is required or Capybara reports it as not present at all, matching the
# pattern used elsewhere in this suite for unopened Bootstrap modals.
Then("the run analysis modal should offer {int} never-analyzed company") do |count|
  expect(page).to have_css("#presentation-target-mode option",
                            text: "Only companies never analyzed (#{count})", visible: :all)
end

Then("the run analysis modal should offer {int} never-analyzed companies") do |count|
  step %(the run analysis modal should offer #{count} never-analyzed company)
end
