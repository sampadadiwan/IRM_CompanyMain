# frozen_string_literal: true

# Steps for the 2026-10 security review follow-up decisions: the RM sale download is owner-only (C4),
# EOI approval is the opportunity firm's (H19), manual insight runs read with the clicker's scope (H17)
# and idle web sessions time out (N7). Design and worked examples: docs/security/security_review_2026_10.md.
#
# Reused from elsewhere:
#   security_c4_c7_h16_l10_steps.rb   — sr_request / sr_sign_in, @c4_parties, "no seller or buyer PAN …"
#   security_h8_h11_h14_h15_h19_steps.rb — sec_rms / "there is an RM … with access to the sale",
#                                          the EOI Background (@eoi, @eoi_lp_user), "the EOI has …"
#   security_h4_h5_h17_n8_steps.rb    — h17_report / "I own a report …"
#   tenant_isolation_batch1_steps.rb  — "I am denied access"

module SecurityDecisionsHelpers
  # H17: replaces the LLM with a fixed answer and keeps the dataset each run attached to its question
  def sd_stub_llm
    @sd_llm_datasets = []
    datasets = @sd_llm_datasets
    chat = double("chat")
    allow(chat).to receive(:ask) do |_prompt, with:|
      # The runner deletes the file after the call, so it is read here, while the LLM "has" it
      datasets << JSON.parse(File.read(with))["dataset"]
      { "md_body" => "## Summary", "charts" => [], "summary_md" => "**Key insight**", "notes" => "test" }.to_json
    end
    # The flag and the cleared mailbox are the ones H17's "no LLM was asked and no insight email was sent" reads
    @h17_llm_asked = false
    allow(LlmService).to receive(:ruby_llm_chat) do
      @h17_llm_asked = true
      chat
    end
    ActionMailer::Base.deliveries.clear
  end

  # H17: the fund names of the commitment rows sent to the LLM by the last run
  def sd_llm_fund_names
    expect(@sd_llm_datasets).not_to be_empty
    fund_ids = @sd_llm_datasets.last.pluck("fund_id").uniq
    Fund.where(id: fund_ids).pluck(:name)
  end

  # H17: a fund of my firm with one LP and one commitment to it
  def sd_fund_with_commitment(name)
    fund = FactoryBot.create(:fund, entity: @entity, name:)
    lp_entity = FactoryBot.create(:entity, name: "#{name} LP", entity_type: "Investor")
    investor = FactoryBot.create(:investor, entity_id: @entity.id, investor_entity_id: lp_entity.id,
                                            investor_name: "#{name} LP", category: "LP")
    FactoryBot.create(:capital_commitment, fund:, entity: @entity, investor:)
    fund
  end

  # H17: users of my firm created by the scenario, by first name
  def sd_employees
    @sd_employees ||= {}
  end
end
World(SecurityDecisionsHelpers)

# ==== C4 follow-up — the RM sale download ======================================================

When('the RM {string} downloads the sale sheet as xlsx') do |name|
  sr_sign_in(sec_rms.fetch(name))
  sr_request(:get, download_secondary_sale_path(@sale, format: :xlsx))
end

Then('the RM {string} may still open the sale') do |name|
  # The refusal is the download's own rule, not a lost grant: the RM still sees the sale
  expect(Pundit.policy(sec_rms.fetch(name), @sale).show?).to be(true)
end

Then("the sale's company admin may download the sale sheet") do
  # The owner-only rule still admits the sale's own firm. Checked on the policy: the sheet's template
  # (download.xlsx.axlsx) raises before rendering for every user - see the scenario's comment
  expect(Pundit.policy(@user, @sale).download?).to be(true)
end

# ==== H19 follow-up — EOI approval ============================================================

Given("the LP's user has the approver role") do
  @eoi_lp_user.add_role(:approver)
  @eoi_lp_user.reload
end

When('the LP approves their EOI') do
  sr_sign_in(@eoi_lp_user)
  sr_request(:patch, approve_expression_of_interest_path(@eoi))
end

Then('the LP may not approve their EOI') do
  expect(Pundit.policy(@eoi_lp_user.reload, @eoi.reload).approve?).to be(false)
end

When('I approve the EOI') do
  # The Background company admin's own session
  sr_request(:patch, approve_expression_of_interest_path(@eoi))
end

# ==== H17 follow-up — manual insight runs use the clicker's scope ==============================

Given('my firm has funds {string} and {string} with one commitment each') do |first, second|
  sd_fund_with_commitment(first)
  sd_fund_with_commitment(second)
end

Given('there is an employee {string} of my firm with access to the fund {string} only') do |first_name, fund_name|
  employee = FactoryBot.create(:user, entity: @entity, first_name:)
  # A plain employee: no company admin role, so the fund scope is the access rights
  employee.remove_role(:company_admin) if employee.has_role?(:company_admin)
  employee.add_role(:employee)
  employee.update_columns(curr_role: "employee")
  # A direct grant on the one fund, as the fund's Access tab gives it
  AccessRight.create!(owner: Fund.find_by!(entity_id: @entity.id, name: fund_name), entity_id: @entity.id,
                      user_id: employee.id, access_type: "Fund", notify: false)
  sd_employees[first_name] = employee.reload
end

When('{string} clicks Generate insight on the report') do |first_name|
  sd_stub_llm
  sr_sign_in(sd_employees.fetch(first_name))
  # The report page's button; the job runs inline in tests
  sr_request(:post, generate_report_insight_report_path(@report))
  @report_insight = @report.report_insights.order(:id).last
end

When("the report's scheduled insight job runs") do
  sd_stub_llm
  # What DailyMorningJob queues: no user and no trigger user
  GenerateReportInsightJob.perform_now(@report.id, user_id: nil)
  @report_insight = @report.report_insights.order(:id).last
end

Then('the data sent to the LLM has only the commitments of {string}') do |fund_names|
  expect(sd_llm_fund_names).to match_array(fund_names.split(",").map(&:strip))
end

Then('the insight is a {string} run triggered by {string}') do |trigger_type, who|
  expect(@report_insight.status).to eq("success")
  expect(@report_insight.trigger_type).to eq(trigger_type)
  expect(@report_insight.triggered_by_user&.first_name).to eq(who == "nobody" ? nil : who)
end

# ==== N7 — session cookie expiry (N7-X) ===========================================================

Then('I am still signed in') do
  expect(page).not_to have_current_path("/users/sign_in")
  expect(page).not_to have_text("Your session expired")
end

When('I keep a copy of my session cookie') do
  # The cookie exactly as the browser sends it (still encoded), as someone copying it would take it
  @sd_cookie_copy = page.driver.browser.rack_mock_session.cookie_jar
                        .get_cookie("_caphive_session").raw[/\A_caphive_session=([^;]*)/, 1]
end

When('I replay the copied session cookie {int} minutes later') do |minutes|
  travel(minutes.minutes)
  # Put the copy back with no Expires, so the browser-side expiry cannot drop it: only the server decides
  page.driver.browser.rack_mock_session.cookie_jar
      .merge("_caphive_session=#{@sd_cookie_copy}; path=/; domain=localhost", URI.parse(page.current_url))
  visit("/")
end

Then('I am sent to sign in') do
  expect(page).to have_current_path("/users/sign_in")
end
