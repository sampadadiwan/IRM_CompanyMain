# frozen_string_literal: true

# Steps for the 2026-10 security review findings H4 (LP assistant document_url checks DocumentPolicy),
# H5 (LP assistant SQL scoped by CTEs) and H17 (report owner not mass-assignable; insights refused
# when the owner is not in the report's firm). Design and worked examples:
# docs/security/security_review_2026_10.md (cards "H4", "H5", "H17").
#
# Reused from elsewhere:
#   lp_assistant_steps.rb  — "an LP scope is set up …" (now with a real LP user, @lp_user),
#                            "the LP requests the URL for that document", "the document response should …",
#                            "the query response should include …"
#   lp_portfolio_steps.rb  — the LP / folio / holdings setup, lp_assistant_query_tool(name),
#                            "the assistant answer should (not) name …"
#   login.rb / common.rb   — "Im logged in as a user … for an entity …", "the user has role …"

module SecurityH4H5H17Helpers
  # H4: a document in the LP's fund, owned by `owner`, in its own folder. Attributes the policy reads
  # (owner, generated / approved, template, private folder) are written with update_columns so no
  # callback or approval flow rewrites them.
  def h4_document(name:, owner:, folder_name:, private_folder: false, generated: false, approved: false, template: false)
    # A fresh folder per document, so its private flag is the one under test
    folder = FactoryBot.create(:folder, name: folder_name, owner: @fund, entity: @fund.entity)
    folder.update_columns(private: true) if private_folder
    document = FactoryBot.create(:document, name:, entity: @fund.entity, folder:, user: @user)
    attributes = { owner_type: owner.class.name, owner_id: owner.id, approved:, template: }
    # A generated document comes from a template: that is what makes it subject to approval
    if generated
      attributes[:owner_tag] = "Generated"
      attributes[:from_template_id] = h4_template.id
    end
    document.update_columns(attributes)
    document
  end

  # The template generated documents point at
  def h4_template
    @h4_template ||= h4_document(name: "SOA Template", owner: @fund, folder_name: "Templates", template: true)
  end

  # H17: one request as the signed-in user through the rack_test driver, the way a crafted form would
  def h17_request(method, path, params = {})
    page.driver.submit(method, path, params)
  end

  # H17: a report of the Artha firm owned by `owner`, on commitments, with an AI prompt
  def h17_report(owner, name)
    Report.create!(user: owner, entity: @entity, name:, curr_role: "employee", url: "/capital_commitments?filter=true",
                   ai_prompt: "Summarise the commitments", send_notification: true,
                   notification_recipients: "cfo@artha.example")
  end

  # H17: runs the insight job as the scheduler / a manual click would, with the LLM replaced by a fixed
  # answer and every LLM client creation recorded
  def h17_run_insight_job
    @h17_llm_asked = false
    chat = double("chat")
    allow(chat).to receive(:ask).and_return(
      { "md_body" => "## Summary", "charts" => [], "summary_md" => "**Key insight**", "notes" => "test" }.to_json
    )
    allow(LlmService).to receive(:ruby_llm_chat) do
      @h17_llm_asked = true
      chat
    end
    ActionMailer::Base.deliveries.clear
    GenerateReportInsightJob.perform_now(@report.id, user_id: @user.id, triggered_by_id: @user.id)
    @report_insight = @report.report_insights.order(:id).last
  end
end
World(SecurityH4H5H17Helpers)

# ---- H4 — LP assistant document_url -----------------------------------------------------------

Given("the LP has a commitment in the LP's fund") do
  # The LP's own investor row in this fund manager's books (created by "an LP scope is set up …")
  investor = Investor.find_by!(entity_id: @fund.entity_id, investor_entity_id: @lp_user.entity_id)
  @lp_commitment = FactoryBot.create(:capital_commitment, fund: @fund, entity: @fund.entity, investor:, folio_id: "LP-001")
  @lp_investor_ids = [investor.id]
end

Given("the LP's own SOA {string} is generated but not approved") do |name|
  @document = h4_document(name:, owner: @lp_commitment, folder_name: "Investor Statements", generated: true)
end

Given("the LP's own SOA {string} is generated and approved") do |name|
  @document = h4_document(name:, owner: @lp_commitment, folder_name: "Investor Statements", generated: true, approved: true)
end

Given("a template {string} in the LP's fund") do |name|
  @document = h4_document(name:, owner: @fund, folder_name: "Templates", template: true)
end

Given("a fund document {string} in a private folder of the LP's fund") do |name|
  @document = h4_document(name:, owner: @fund, folder_name: "Board", private_folder: true)
end

Given("an unreleased notice {string} generated for a capital call of the LP's fund") do |name|
  # An uploaded-basis call: no percentage maths, just the call the notice belongs to
  call = FactoryBot.create(:capital_call, fund: @fund, entity: @fund.entity, call_basis: "Upload")
  @document = h4_document(name:, owner: call, folder_name: "Capital Calls", generated: true)
end

Given("a data room document {string} of the LP's fund") do |name|
  # The LP's access right on the fund (from the scope step) is what lets them open it
  @document = h4_document(name:, owner: @fund, folder_name: "Data Room")
end

Then("the document response should be a download URL") do
  # The stubbed signed URL from "the LP requests the URL for that document"
  expect(@document_response).to eq("https://s3.example.test/doc.pdf")
end

# ---- H5 — LP assistant SQL tool ---------------------------------------------------------------

Given("the investor {string} has PAN {string}") do |name, pan|
  Investor.find_by!(entity_id: @user.entity_id, investor_name: name).update_columns(pan:)
end

When("LP {string} runs the assistant query {string}") do |name, sql|
  # The real LpChatProvider wiring (lp_portfolio_steps.rb); the LLM is replaced by the fixed SQL
  @run_query_response = lp_assistant_query_tool(name).execute(sql:)
  puts "\n####RunQueryTool response####\n#{@run_query_response}\n"
end

When("LP {string} runs the first example query of every LP assistant skill") do |name|
  # H5-H drift guard: each skill's first ```sql block, run exactly as documented
  @skill_example_responses = Rails.root.glob("app/packs/ai/lp_assistant/skills/*.md").sort.to_h do |path|
    sql = path.read[/```sql\n(.*?)```/m, 1]
    [path.basename(".md").to_s, sql ? lp_assistant_query_tool(name).execute(sql:) : "(no sql example)"]
  end
  @skill_example_responses.each { |skill, response| puts "\n#####{skill}####\n#{response}\n" }
end

Then("every skill's first example query executes") do
  # Executes = neither refused by validation nor failed in the database (an empty result is fine)
  failures = @skill_example_responses.select do |_skill, response|
    response.start_with?("Query rejected", "SQL execution failed", "(no sql example)", "No ")
  end
  expect(failures).to be_empty
end

# ---- H17 — Report owner mass assignment -------------------------------------------------------

Given("there is another firm {string} with a user {string}") do |firm_name, first_name|
  @other_firm = FactoryBot.create(:entity, name: firm_name, entity_type: "Investment Fund")
  @other_firm_user = FactoryBot.create(:user, entity: @other_firm, first_name:)
end

Given("I own a report {string}") do |name|
  @report = h17_report(@user, name)
end

Given("a user {string} of my firm owns a report {string}") do |first_name, name|
  # e.g. a support user while switched into this firm: at creation the owner is in the report's firm
  @report_owner = FactoryBot.create(:user, entity: @entity, first_name:)
  @report = h17_report(@report_owner, name)
end

Given("the report's owner has moved to {string}") do |firm_name|
  # The owner left the firm, or a support owner is now switched into another tenant
  @report_owner.update_columns(entity_id: Entity.find_by!(name: firm_name).id)
end

When("I update the report sending {string} of {string} as its owner and firm") do |first_name, firm_name|
  firm = Entity.find_by!(name: firm_name)
  victim = User.find_by!(entity_id: firm.id, first_name:)
  h17_request(:patch, "/reports/#{@report.id}", report: { name: "Renamed by form", user_id: victim.id, entity_id: firm.id })
end

When("I update the report's notification recipients to {string}") do |recipients|
  h17_request(:patch, "/reports/#{@report.id}", report: { notification_recipients: recipients })
end

When("I rename the report to {string}") do |name|
  h17_request(:patch, "/reports/#{@report.id}", report: { name: })
end

Then("the report is still owned by {string} of {string}") do |first_name, firm_name|
  @report.reload
  expect(@report.user.first_name).to eq(first_name)
  expect(@report.entity).to eq(Entity.find_by!(name: firm_name))
end

Then("re-owning the report to {string} directly is refused") do |first_name|
  # The model rule (H17 fix 2) holds even where params are not the path
  victim = User.find_by!(first_name:)
  @report.reload.user = victim
  expect(@report.save).to be(false)
  expect(@report.errors[:user]).to include("must be in this record's firm")
end

Then("the report is saved with name {string}") do |name|
  expect(@report.reload.name).to eq(name)
end

Then("the report is saved with notification recipients {string}") do |recipients|
  expect(@report.reload.notification_recipients).to eq(recipients)
end

When("the report's insight job runs") do
  h17_run_insight_job
end

Then("the insight fails with {string}") do |message|
  expect(@report_insight.status).to eq("failed")
  expect(@report_insight.status_message).to eq(message)
end

Then("no LLM was asked and no insight email was sent") do
  expect(@h17_llm_asked).to be(false)
  expect(ActionMailer::Base.deliveries.map(&:subject).grep(/Key Insights/)).to be_empty
end

Then("the insight is generated") do
  expect(@report_insight.status).to eq("success")
  expect(@h17_llm_asked).to be(true)
end

# ---- N8 — support agent run target ------------------------------------------------------------
# features/security/support_agent_run_target.feature. Reused: "{string} is a fund manager at … with the fund …"
# and "Golden Angels has the {string} agent {string} with chat on" (ai_chat_steps.rb, @agents by type),
# "a portfolio company {string} exists" (ai_portfolio_reports_steps.rb), and c3_send / "I am refused" /
# "the request succeeds" (security_c3_h3_steps.rb). Requests go through the rack-test browser as the run
# modal and the agent's Run Now button send them.

module SecurityN8Helpers
  # The record a scenario names by type and name, in either firm
  def n8_record(type, name)
    case type
    when "Investor" then Investor.find_by!(investor_name: name)
    when "Entity" then Entity.find_by!(name:)
    when "Fund" then Fund.find_by!(name:)
    else raise ArgumentError, "N8 steps know no #{type}"
    end
  end

  # One run request: the run modal posts to support_agents#run by agent_type; the Run Now button posts to
  # support_agents#run_with_steps on the agent's id
  def n8_run(endpoint, agent_type, params)
    case endpoint
    when "run" then c3_send(:post, run_support_agents_path, params.merge(agent_type:))
    when "run_with_steps" then c3_send(:post, run_with_steps_support_agent_path(@agents.fetch(agent_type)), params)
    else raise ArgumentError, "N8 steps know no endpoint #{endpoint}"
    end
  end

  # What a refused run must leave unchanged: every agent report and document, in any firm
  def n8_counts
    { reports: SupportAgentReport.count, documents: Document.count }
  end
end
World(SecurityN8Helpers)

Given("another firm {string} has a portfolio company {string} and a fund {string}") do |firm, company, fund|
  # Zeta: a tenant of its own, with a portfolio company and a fund Priya's agents must never reach
  @n8_zeta = FactoryBot.create(:entity, name: firm, entity_type: "Investment Fund")
  FactoryBot.create(:investor, name: company, category: "Portfolio Company", entity: @n8_zeta,
                               investor_entity: FactoryBot.create(:entity, entity_type: "Company"))
  FactoryBot.create(:fund, entity: @n8_zeta, name: fund)
end

Given("the support agents are watched and must not run") do
  # Every agent class Priya has: entering its pipeline (call for step runs, wtf? otherwise) is recorded
  @n8_agent_runs = []
  @agents.each_value do |agent|
    %i[call wtf?].each do |entry|
      allow(agent.agent).to receive(entry) { |**| @n8_agent_runs << agent.agent_type }
    end
  end
  # Taken after the set-up, so only what the run creates counts
  @n8_counts_before = n8_counts
end

Given("the LLM is stubbed for the agent run") do
  # N8-H: as portfolio_company_agent_steps.rb — SupportAgentService#initialize_agent always builds an LLM
  # chat, so stub at the service layer; the agents' own steps run for real
  allow(LlmService).to receive(:ruby_llm_chat).and_return(double("chat", ask: double(content: "mocked response")))
end

When("Priya runs the {string} agent through {string} on the {word} {string}") do |agent_type, endpoint, type, name|
  n8_run(endpoint, agent_type, { target_type: type, target_id: n8_record(type, name).id })
end

When("Priya runs the {string} agent on the {word} {string} with an RTA statement PDF") do |agent_type, type, name|
  # The RTA modal's multipart post: the PDF is saved as a Document on the target before the job runs
  pdf = Rack::Test::UploadedFile.new(Rails.public_path.join("sample_uploads/SignedDoc.pdf"), "application/pdf")
  n8_run("run", agent_type, { target_type: type, target_id: n8_record(type, name).id, rta_pdf: pdf })
end

When("Priya runs the {string} agent through {string} with target type {string}") do |agent_type, endpoint, target_type|
  # N8-X: a real id of the firm's own, so only the type is wrong
  n8_run(endpoint, agent_type, { target_type:, target_id: @portfolio_company.id })
end

When("the {string} job is performed for target type {string} with the id of the {word} {string}") do |agent_type, target_type, type, name|
  # N8-2: the job as any enqueuing path would call it, bypassing the controller
  SupportAgentJob.perform_now(support_agent_id: @agents.fetch(agent_type).id, target_type:,
                              target_id: n8_record(type, name).id, user_id: @user.id, with_steps: true,
                              execution_mode: :single_company_with_steps)
end

Then("the run is not found") do
  expect(@c3_response.status).to eq(404)
end

Then("no agent ran and no agent report or document was created") do
  expect(@n8_agent_runs).to be_empty
  expect(n8_counts).to eq(@n8_counts_before)
end

Then("the {string} run is logged as failed with {string}") do |agent_type, message|
  log = AgentExecutionLog.where(support_agent: @agents.fetch(agent_type)).order(:id).last
  expect(log.status).to eq("failed")
  expect(log.error_message).to include(message)
end

Then("the {string} agent ran once on the {word} {string}") do |agent_type, type, name|
  agent = @agents.fetch(agent_type)
  target = n8_record(type, name)
  # The job got past the firm check and processed exactly this record, without an error
  log = AgentExecutionLog.where(support_agent: agent).order(:id).last
  expect(log.status).to eq("completed")
  expect(log.result_summary).to include("total" => 1, "processed" => 1, "failed" => 0)
  # The run's report sits on the firm's own record
  expect(SupportAgentReport.where(support_agent: agent, owner: target)).to exist
end
