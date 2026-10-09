# frozen_string_literal: true

# ── Helpers ──────────────────────────────────────────────────────────────────

# Builds or finds the SupportAgent for PortfolioCompanyAgent on @entity.
def build_portfolio_company_agent(entity, flags)
  SupportAgent.find_or_create_by!(agent_type: "PortfolioCompanyAgent", entity: entity) do |agent|
    agent.name        = "Portfolio Company Analyst"
    agent.enabled     = true
    agent.llm_model   = "gemini-3.7-flash"
    agent.json_fields = flags
  end
end

# Returns [prev_period_end, due_date] for the quarter the agent validates.
# prev_period_end equals the agent's check_date (compute_check_period): the most
# recently completed quarter-end. The agent's data query range is
# period_start..period_end == (quarter start)..prev_period_end.
def portco_kpi_window
  due_date    = Date.end_of_period("Quarter") - 15.days
  prev_period = Date.previous_end_of_period("Quarter", due_date)
  [prev_period, due_date]
end

# A KPI as_of date the agent's look-back query will find.
# Since the look-back refactor, check_kpi_submission queries
# as_of: period_start..period_end (the COMPLETED period, e.g. Apr 1..Jun 30) —
# a date after period_end (the old "+1 day" here) falls outside the range,
# silently skipping the document check (@last_kpi_report stays nil).
# The period end itself is the canonical quarter-end reporting date.
def kpi_as_of_in_window
  prev_period, _due_date = portco_kpi_window
  prev_period
end

# PortfolioCompanyAgent is deterministic and never uses the LLM, but
# SupportAgentService#initialize_agent unconditionally calls LlmService.ruby_llm_chat,
# which requires API keys. Stub at the service layer, not RubyLLM directly (see
# call_notice_agent_steps.rb for the same pattern).
def stub_llm_service
  mock_chat = double('chat', ask: double(content: 'mocked response'))
  allow(LlmService).to receive(:ruby_llm_chat).and_return(mock_chat)
end

# ── Background / agent configuration ─────────────────────────────────────────

Given("the portfolio company agent is enabled") do
  @support_agent = build_portfolio_company_agent(@entity, {})
end

Given("the portfolio company agent is disabled") do
  @support_agent = build_portfolio_company_agent(@entity, {})
  @support_agent.update!(enabled: false)
end

Given("the portfolio company agent has KPI reminders enabled for today") do
  # Configure reminder_days to include today's offset from quarter start so the
  # reminder fires deterministically regardless of when the test suite runs.
  today        = Time.zone.today
  days_elapsed = (today - today.beginning_of_quarter).to_i
  # kpi_reminder_recipients is required: send_kpi_reminder skips (no email) when
  # no explicit recipients are configured, rather than falling back to the
  # fund's employees.
  @support_agent.update!(json_fields: (@support_agent.json_fields || {}).merge(
    "send_kpi_reminder"       => "true",
    "reminder_days"           => days_elapsed.to_s,
    "kpi_reminder_recipients" => "cfo@testcorp.example.com"
  ))
  ActionMailer::Base.deliveries.clear
end

Given("the portfolio company agent requires a {string} document") do |doc_name|
  @support_agent.update!(json_fields: (@support_agent.json_fields || {}).merge(
    "validate_documents" => "true",
    "required_docs"      => doc_name
  ))
end

# ── Portfolio company / data setup ────────────────────────────────────────────

Given("there is also a portfolio company {string}") do |args|
  steps %(Given there is an existing portfolio company "#{args}")
  @second_portfolio_company = @investor
  # Restore @portfolio_company so subsequent steps target the original company.
  @portfolio_company = Investor.find_by(investor_name: "TestCorp", entity: @entity)
end

Given("the portfolio company has submitted KPIs for the current period") do
  @kpi_report = FactoryBot.create(
    :kpi_report,
    portfolio_company: @portfolio_company,
    entity:            @entity,
    user:              @user,
    as_of:             kpi_as_of_in_window,
    period:            "Quarter"
  )
end

Given("the portfolio company has no KPI reports") do
  @portfolio_company.portfolio_kpi_reports.destroy_all
end

Given("the portfolio company has a recent valuation") do
  prev_period, _due_date = portco_kpi_window
  instrument = FactoryBot.create(:investment_instrument, entity: @entity, portfolio_company: @portfolio_company)
  FactoryBot.create(
    :valuation,
    owner:                 @portfolio_company,
    entity:                @entity,
    investment_instrument: instrument,
    # Must be INSIDE the completed period (period_start..period_end) — the agent
    # queries valuation_date in that range; +1.day would fall outside it.
    valuation_date:        prev_period
  )
end

Given("the portfolio company has no valuations") do
  @portfolio_company.valuations.destroy_all
end

Given("the KPI report has no documents uploaded") do
  @kpi_report&.documents&.destroy_all
end

Given("a KPI reminder was already sent today for the portfolio company") do
  # Pre-seed a SupportAgentReport so the duplicate-send guard fires.
  report = SupportAgentReport.find_or_initialize_by(
    owner:         @portfolio_company,
    support_agent: @support_agent
  )
  report.json_fields = {
    "kpi_issues"              => [],
    "document_issues"         => [],
    "valuation_issues"        => [],
    "final_status"            => "blocked",
    "last_kpi_reminder_sent_at" => Time.zone.today.iso8601
  }
  report.status = :completed
  report.save!
end

# ── Agent execution ───────────────────────────────────────────────────────────

When("I run the portfolio company agent") do
  stub_llm_service
  PortfolioCompanyAgent.call(
    support_agent_id: @support_agent.id,
    target:           @portfolio_company
  )
  @report = SupportAgentReport.find_by(owner: @portfolio_company, support_agent: @support_agent)
  @report&.reload
end

When("I run the portfolio company agent for the LP investor") do
  stub_llm_service
  PortfolioCompanyAgent.call(
    support_agent_id: @support_agent.id,
    target:           @investor
  )
  @report_for_lp = SupportAgentReport.find_by(owner: @investor, support_agent: @support_agent)
end

When("I run the portfolio company agent in batch mode") do
  stub_llm_service
  targets = Investor.where(
    id:       [@portfolio_company.id, @second_portfolio_company.id],
    entity:   @entity,
    category: "Portfolio Company"
  )
  @batch_result = PortfolioCompanyAgent.process_batch(
    support_agent_id: @support_agent.id,
    targets:          targets,
    user_id:          @user.id,
    entity_id:        @entity.id,
    execution_mode:   :adhoc_batch
  )
end

# ── Assertions ────────────────────────────────────────────────────────────────

Then("the portfolio agent report final status should be {string}") do |expected|
  expect(@report).to be_present,
    "Expected a SupportAgentReport for #{@portfolio_company.investor_name} but none was found"
  expect(@report.final_status).to eq(expected)
end

Then("no portfolio agent report should be created") do
  report = SupportAgentReport.find_by(owner: @portfolio_company, support_agent: @support_agent)
  expect(report).to be_nil,
    "Expected no SupportAgentReport but found one with status=#{report&.final_status}"
end

Then("no portfolio agent report should be created for the LP investor") do
  report = SupportAgentReport.find_by(owner: @investor, support_agent: @support_agent)
  expect(report).to be_nil,
    "Expected no SupportAgentReport for the LP investor but one was created"
end

Then("the portfolio agent report should have a successful KPI issue") do
  kpi_issues = @report.json_fields["kpi_issues"] || []
  success = kpi_issues.any? { |i| i["severity"] == "success" }
  expect(success).to be(true),
    "Expected a success-severity KPI issue but got: #{kpi_issues.inspect}"
end

Then("the portfolio agent report should have a blocking KPI issue") do
  kpi_issues = @report.json_fields["kpi_issues"] || []
  blocking = kpi_issues.any? { |i| i["severity"] == "blocking" }
  expect(blocking).to be(true),
    "Expected a blocking KPI issue but got: #{kpi_issues.inspect}"
end

Then("the portfolio agent report should have a successful valuation issue") do
  valuation_issues = @report.json_fields["valuation_issues"] || []
  success = valuation_issues.any? { |i| i["severity"] == "success" }
  expect(success).to be(true),
    "Expected a success-severity valuation issue but got: #{valuation_issues.inspect}"
end

Then("the portfolio agent report should have a blocking valuation issue") do
  valuation_issues = @report.json_fields["valuation_issues"] || []
  blocking = valuation_issues.any? { |i| i["severity"] == "blocking" }
  expect(blocking).to be(true),
    "Expected a blocking valuation issue but got: #{valuation_issues.inspect}"
end

Then("the portfolio agent report should have a blocking document issue mentioning {string}") do |text|
  document_issues = @report.json_fields["document_issues"] || []
  matching = document_issues.select do |i|
    i["severity"] == "blocking" && i["message"]&.include?(text)
  end
  expect(matching).not_to be_empty,
    "Expected a blocking document issue mentioning '#{text}' but got: #{document_issues.inspect}"
end

Then("the portfolio agent report should not have a blocking document issue") do
  document_issues = @report.json_fields["document_issues"] || []
  blocking = document_issues.select { |i| i["severity"] == "blocking" }
  expect(blocking).to be_empty,
    "Expected no blocking document issues but got: #{blocking.inspect}"
end

Then("a KPI reminder email should have been sent") do
  expect(ActionMailer::Base.deliveries).not_to be_empty,
    "Expected a KPI reminder email to be delivered but ActionMailer::Base.deliveries is empty"
end

Then("no KPI reminder email should have been sent") do
  expect(ActionMailer::Base.deliveries).to be_empty,
    "Expected no KPI reminder email but #{ActionMailer::Base.deliveries.count} was delivered"
end

Then("the portfolio agent report should record that a reminder was sent today") do
  expect(@report).to be_present
  sent_at = @report.json_fields["last_kpi_reminder_sent_at"]
  expect(sent_at).to eq(Time.zone.today.iso8601),
    "Expected last_kpi_reminder_sent_at=#{Time.zone.today.iso8601} but got #{sent_at.inspect}"
end

Then("the batch result should show {int} successes and {int} errors") do |success_count, error_count|
  expect(@batch_result[:successes].count).to eq(success_count),
    "Expected #{success_count} successes but got #{@batch_result[:successes].count}: #{@batch_result[:successes].inspect}"
  expect(@batch_result[:errors].count).to eq(error_count),
    "Expected #{error_count} errors but got #{@batch_result[:errors].count}: #{@batch_result[:errors].inspect}"
end
