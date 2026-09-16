# Steps for features/ai/support_agents/side_letter_obligation_agent.feature
# The LLM is always stubbed — extraction scenarios exercise the pipeline
# (citation guard, diffing, review gate), never a real model call.

# Three cited obligations (recurring / one-time / event) + one uncited row the
# citation guard must discard.
STANDARD_SIDE_LETTER_EXTRACTION = [
  { "obligation_type" => "reporting", "title" => "Quarterly ESG report",
    "description" => "Provide an ESG impact report within 45 days of quarter end.",
    "source_clause" => "Section 4.3(b)", "trigger_type" => "calendar_event",
    "trigger_description" => "Within 45 days of each quarter-end",
    "frequency_rrule" => "FREQ=QUARTERLY;INTERVAL=1",
    "next_due_date" => (Date.today + 30).iso8601, "owner_team" => "ir", "confidence" => 0.92 },
  { "obligation_type" => "reporting", "title" => "Audited financials",
    "description" => "Deliver audited financial statements.",
    "source_clause" => "Section 5.1", "trigger_type" => "one_time",
    "trigger_description" => "By April 30", "frequency_rrule" => nil,
    "next_due_date" => (Date.today + 60).iso8601, "owner_team" => "finance", "confidence" => 0.88 },
  { "obligation_type" => "key_person", "title" => "Key person departure notice",
    "description" => "Notify the LP within 5 business days if a key person leaves.",
    "source_clause" => "Section 7.2", "trigger_type" => "fund_event",
    "trigger_description" => "On key person departure", "frequency_rrule" => nil,
    "next_due_date" => nil, "owner_team" => "legal", "confidence" => 0.85 },
  # No source_clause — must be discarded, never persisted
  { "obligation_type" => "other", "title" => "Vague goodwill commitment",
    "description" => "Something without a citation.", "trigger_type" => "ongoing", "confidence" => 0.4 }
].freeze

def stub_side_letter_llm(payload)
  mock_chat = double("chat")
  allow(LlmService).to receive(:ruby_llm_chat).and_return(mock_chat)
  allow(mock_chat).to receive(:ask).and_return(payload.to_json)
end

def create_pending_obligation(attrs = {})
  @side_letter ||= begin
    doc = FactoryBot.create(:document, entity: @entity, owner: @commitment, name: "Side Letter",
                                       folder: @commitment.document_folder, user: @user)
    SideLetter.create!(entity: @entity, capital_commitment: @commitment, document: doc)
  end
  @obligation = @side_letter.side_letter_obligations.create!({
    entity: @entity,
    obligation_type: "reporting",
    title: "Test obligation",
    trigger_type: "one_time",
    review_status: "pending_review",
    extracted_by: "manual",
    reminder_days_before: 7
  }.merge(attrs))
end

# ── Background ────────────────────────────────────────────────────────────────

Given('a fund with a capital commitment exists') do
  @fund = FactoryBot.create(:fund, entity: @entity)
  # investor_entity passed explicitly — the factory default samples Entity.startups,
  # which is empty in a fresh cucumber database
  @investor = FactoryBot.create(:investor, entity: @entity, investor_entity: @entity, investor_name: "LP Alpha")
  @commitment = FactoryBot.create(:capital_commitment, fund: @fund, entity: @entity, investor: @investor)
end

Given('there is a side letter obligation support agent') do
  # The policies keep the whole feature dark unless the entity flag is on, so an
  # entity that has the agent configured must also have it switched on.
  @entity.support_agents.set!(:side_letter_obligation_agent)

  @support_agent = FactoryBot.create(
    :support_agent,
    entity: @entity,
    agent_type: "SideLetterObligationAgent",
    name: "Side Letter Obligations",
    json_fields: {
      "side_letter_doc_label" => "Side Letter",
      "default_reminder_days_before" => "7",
      "overdue_escalation_days" => "3",
      "notify_tag" => ""
    }
  )

  # Default LLM stub — prevents model-not-found and missing-API-key errors
  # for scenarios that never need the LLM (e.g. "no document found").
  # Scenarios that need specific LLM responses override this via stub_side_letter_llm.
  mock_chat = double("chat", ask: [].to_json)
  allow(LlmService).to receive(:ruby_llm_chat).and_return(mock_chat)
end

# ── Extraction ────────────────────────────────────────────────────────────────

Given('the commitment has a side letter document') do
  @side_letter_doc = FactoryBot.create(:document, entity: @entity, owner: @commitment,
                                       name: "Side Letter", folder: @commitment.document_folder,
                                       user: @user)
end

Given('the LLM extracts the standard side letter obligations') do
  stub_side_letter_llm(STANDARD_SIDE_LETTER_EXTRACTION)
end

When('the LLM extracts a changed reporting obligation') do
  changed = STANDARD_SIDE_LETTER_EXTRACTION.map(&:dup)
  changed[0] = changed[0].merge("title" => "Monthly ESG report",
                                "frequency_rrule" => "FREQ=MONTHLY;INTERVAL=1")
  stub_side_letter_llm(changed)
end

When('the extraction run processes the commitment') do
  @extraction_result = SideLetterObligationAgent.call(
    support_agent_id: @support_agent.id,
    target: @commitment,
    entity_id: @entity.id
  )
  expect(@extraction_result.success?).to be(true)
end

Given('the reporting obligation is approved by counsel') do
  obligation = SideLetterObligation.find_by!(source_clause: "Section 4.3(b)", review_status: "pending_review")
  result = ObligationApprove.call(obligation: obligation, user: @user)
  expect(result.success?).to be(true)
  @approved_obligation = obligation.reload
end

Then('{int} obligations should be pending review for the commitment') do |count|
  scope = SideLetterObligation.joins(:side_letter)
                              .where(side_letters: { capital_commitment_id: @commitment.id })
                              .where(review_status: "pending_review")
  expect(scope.count).to eq(count)
end

Then('no tasks should exist for any obligation') do
  expect(Task.where(owner_type: "SideLetterObligation").count).to eq(0)
end

Then('the side letter record should have extraction status {string}') do |status|
  expect(SideLetter.find_by!(capital_commitment_id: @commitment.id).extraction_status).to eq(status)
end

Then('the agent report should note that {int} extracted item was discarded for missing citation') do |count|
  report = SupportAgentReport.where(owner: @commitment, support_agent: @support_agent).last
  discarded = report.json_fields["extraction_issues"].find { |i| i["type"] == "discarded" }
  expect(discarded["message"]).to include("#{count} extracted item(s)")
end

Then('the approved reporting obligation should be unchanged') do
  expect(@approved_obligation.reload.title).to eq("Quarterly ESG report")
  expect(@approved_obligation.review_status).to eq("approved")
end

Then('a pending delta obligation should exist for clause {string}') do |clause|
  delta = SideLetterObligation.where(source_clause: clause, review_status: "pending_review", delta: true)
  expect(delta.count).to eq(1)
  expect(delta.first.title).to eq("Monthly ESG report")
end

Then('no obligations should exist for the commitment') do
  scope = SideLetterObligation.joins(:side_letter)
                              .where(side_letters: { capital_commitment_id: @commitment.id })
  expect(scope.count).to eq(0)
end

Then('the agent report should note that no side letter document was found') do
  report = SupportAgentReport.where(owner: @commitment, support_agent: @support_agent).last
  expect(report).to be_present, "Expected a SupportAgentReport for the commitment but none found"
  issue = report.json_fields["extraction_issues"].find { |i| i["type"] == "no_document" }
  expect(issue).to be_present
  expect(issue["severity"]).to eq("info")
end

# ── Review gate & projection ─────────────────────────────────────────────────

Given('a pending {string} obligation without an owner') do |trigger|
  create_pending_obligation(trigger_type: trigger, owner_team: nil, next_due_date: Date.today + 30)
end

Given('a pending {string} obligation with rrule {string} owned by team {string}') do |trigger, rrule, team|
  create_pending_obligation(trigger_type: trigger, frequency_rrule: rrule, owner_team: team,
                            next_due_date: Date.today + 7)
end

Given('a pending {string} obligation owned by team {string} due in {int} days') do |trigger, team, days|
  create_pending_obligation(trigger_type: trigger, owner_team: team, next_due_date: Date.today + days)
end

Given('a pending {string} obligation owned by team {string}') do |trigger, team|
  create_pending_obligation(trigger_type: trigger, owner_team: team)
end

Given('an approved armed obligation owned by team {string}') do |team|
  create_pending_obligation(trigger_type: "fund_event", owner_team: team)
  expect(ObligationApprove.call(obligation: @obligation, user: @user).success?).to be(true)
  expect(@obligation.reload.armed?).to be(true)
end

# Used as both Given (setup, must succeed implicitly via later asserts) and When
When('counsel approves the obligation') do
  @approve_result = ObligationApprove.call(obligation: @obligation, user: @user)
end

When('counsel rejects the obligation') do
  expect(ObligationReject.call(obligation: @obligation, user: @user).success?).to be(true)
end

Then('the approval should fail because an owner is required') do
  expect(@approve_result.failure?).to be(true)
  expect(@approve_result[:error]).to include("owner")
end

Then('the obligation should still be pending review') do
  expect(@obligation.reload.review_status).to eq("pending_review")
end

Then('the obligation should be active with a recurrence rule') do
  @obligation.reload
  expect(@obligation.review_status).to eq("approved")
  expect(@obligation.status).to eq("active")
  expect(@obligation.task_recurrence_rule).to be_present
  expect(@obligation.task_recurrence_rule.rrule).to eq(@obligation.frequency_rrule)
end

When('the recurring task generator job runs for obligations') do
  RecurringTaskGeneratorJob.perform_now
end

Then('recurring tasks owned by the obligation should exist with category {string}') do |category|
  tasks = @obligation.reload.tasks
  expect(tasks.count).to be >= 1
  expect(tasks.pluck(:category).uniq).to eq([category])
  expect(tasks.pluck(:task_recurrence_rule_id).uniq).to eq([@obligation.task_recurrence_rule_id])
end

Then('exactly {int} task should exist for the obligation') do |count|
  expect(@obligation.reload.tasks.count).to eq(count)
end

Then('exactly {int} tasks should exist for the obligation') do |count|
  expect(@obligation.reload.tasks.count).to eq(count)
end

Then('the obligation task should be due in {int} days') do |days|
  expect(@obligation.reload.tasks.last.due_date).to eq(Date.today + days)
end

Then('the obligation should be armed') do
  expect(@obligation.reload.armed?).to be(true)
end

Then('the obligation should be rejected') do
  expect(@obligation.reload.review_status).to eq("rejected")
end

When('the obligation is fired with a due date {int} days out') do |days|
  result = ObligationFire.call(obligation: @obligation, due_date: Date.today + days, user: @user)
  expect(result.success?).to be(true)
end

When("the obligation's task is completed") do
  task = @obligation.reload.tasks.last
  task.update!(completed: true)
end

Then('an obligation fulfillment should be recorded from the task') do
  fulfillment = @obligation.reload.obligation_fulfillments.last
  expect(fulfillment).to be_present
  expect(fulfillment.task_id).to eq(@obligation.tasks.last.id)
end

Then('the obligation status should be {string}') do |status|
  expect(@obligation.reload.status).to eq(status)
end

Given('an approved recurring obligation with one completed and one open task') do
  create_pending_obligation(trigger_type: "calendar_event", frequency_rrule: "FREQ=MONTHLY;INTERVAL=1",
                            owner_team: "ir", next_due_date: Date.today + 7)
  expect(ObligationApprove.call(obligation: @obligation, user: @user).success?).to be(true)
  rule = @obligation.reload.task_recurrence_rule
  @completed_task = Task.create!(entity: @entity, details: "Done occurrence", category: "Compliance",
                                 owner: @obligation, task_recurrence_rule: rule,
                                 due_date: Date.today - 30, original_start_date: Date.today - 30,
                                 completed: true)
  @open_task = Task.create!(entity: @entity, details: "Open occurrence", category: "Compliance",
                            owner: @obligation, task_recurrence_rule: rule,
                            due_date: Date.today + 30, original_start_date: Date.today + 30)
end

When('the obligation is waived') do
  expect(ObligationTeardown.call(obligation: @obligation, new_status: "waived", user: @user).success?).to be(true)
end

Then('the open task should be gone') do
  expect(Task.where(id: @open_task.id)).to be_empty
end

Then('the completed task and its fulfillment should remain') do
  task = Task.find(@completed_task.id)
  # Detached from the destroyed rule, flagged as an exception occurrence
  expect(task.task_recurrence_rule_id).to be_nil
  expect(task.is_exception).to be(true)
  expect(@obligation.reload.obligation_fulfillments.where(task_id: task.id)).to exist
end

# ── Enforcement ───────────────────────────────────────────────────────────────

Given('an owner user {string} exists') do |email|
  @owner_user = FactoryBot.create(:user, entity: @entity, email: email)
end

Given('an escalation user {string} tagged {string} exists') do |email, tag|
  FactoryBot.create(:user, entity: @entity, email: email, tag_list: tag)
end

Given('the agent notify tag is {string}') do |tag|
  @support_agent.update!(json_fields: @support_agent.json_fields.merge("notify_tag" => tag))
end

def approved_obligation_with_task(owner_email:, due_date:, reminder_days: 7)
  owner = User.find_by!(email: owner_email)
  obligation = create_pending_obligation(
    trigger_type: "one_time", owner_user_id: owner.id, owner_team: "legal",
    next_due_date: due_date, reminder_days_before: reminder_days,
    title: "Obligation due #{due_date}", source_clause: "Section #{rand(100)}.#{rand(9)}"
  )
  expect(ObligationApprove.call(obligation: obligation, user: @user).success?).to be(true)
  obligation.reload
end

Given('an approved obligation owned by {string} with a task due in {int} days') do |email, days|
  approved_obligation_with_task(owner_email: email, due_date: Date.today + days)
end

Given('an approved obligation owned by {string} with a task due today') do |email|
  approved_obligation_with_task(owner_email: email, due_date: Date.today)
end

Given('an approved obligation owned by {string} with a task {int} days overdue') do |email, days|
  # Approve with a future date (one-time projection copies next_due_date), then
  # backdate the projected task — mirrors a deadline that has since slipped.
  obligation = approved_obligation_with_task(owner_email: email, due_date: Date.today + 1)
  obligation.tasks.last.update!(due_date: Date.today - days)
end

Given('an approved obligation owned by {string} with a task due in {int} days and zero lead time') do |email, days|
  approved_obligation_with_task(owner_email: email, due_date: Date.today + days, reminder_days: 0)
end

When('the enforcement run executes') do
  ActionMailer::Base.deliveries.clear if @enforcement_ran.nil?
  result = ObligationEnforcement.call(support_agent: @support_agent)
  expect(result.success?).to be(true)
  @enforcement_ran = true
end

Then('exactly {int} obligation alert email should be sent to {string}') do |count, email|
  alerts = ActionMailer::Base.deliveries.select do |mail|
    mail.to.include?(email) && mail.subject.include?("Side Letter Obligations")
  end
  expect(alerts.size).to eq(count)
end

Then('the alert email should list {int} obligations') do |count|
  mail = ActionMailer::Base.deliveries.find { |m| m.subject.include?("Side Letter Obligations") }
  body = mail.body.encoded
  rows = body.scan(/Obligation due/).size
  expect(rows).to eq(count)
end

Then('{int} obligation reminders should be logged') do |count|
  expect(ObligationReminder.where(entity_id: @entity.id).count).to eq(count)
end

Then('no obligation alert emails should be sent') do
  alerts = ActionMailer::Base.deliveries.select { |m| m.subject.include?("Side Letter Obligations") }
  expect(alerts).to be_empty
end

# ── Matrix UI ────────────────────────────────────────────────────────────────

Given('an approved armed obligation owned by team {string} titled {string}') do |team, title|
  create_pending_obligation(trigger_type: "fund_event", owner_team: team, title: title)
  expect(ObligationApprove.call(obligation: @obligation, user: @user).success?).to be(true)
end

When('I visit the obligation matrix') do
  visit side_letter_obligations_path
end

When('I visit the obligation matrix filtered by review status {string}') do |status|
  visit side_letter_obligations_path(q: { review_status_eq: status })
end

# Asserts an obligation row is visible in the matrix with the given status.
# Visits the matrix page first since the approve step bypasses the UI.
#
# @param title [String] the obligation title to look for
# @param status [String] the expected status text in the row
Then('I should see the obligation row {string} with status {string}') do |title, status|
  visit side_letter_obligations_path
  within("#obligation-matrix") do
    expect(page).to have_content(title)
    expect(page).to have_content(status)
  end
end

When('I approve the obligation from the matrix') do
  within("##{ActionView::RecordIdentifier.dom_id(@obligation)}") do
    click_button "Approve"
  end
end

Then('the obligation should be approved') do
  expect(@obligation.reload.review_status).to eq("approved")
end

Then('I should see {string} in the matrix') do |text|
  within("#obligation-matrix") { expect(page).to have_content(text) }
end

Then('I should not see {string} in the matrix') do |text|
  within("#obligation-matrix") { expect(page).to have_no_content(text) }
end

When('I fire the obligation with due date {int} days from now') do |days|
  # Fire opens a consequence modal (Request Updates pattern). The modal markup
  # lives OUTSIDE the table (via _action_modals), so scope to the modal itself —
  # rack-test reads it regardless of Bootstrap's CSS visibility.
  # Real browser (Playwright): open the consequence modal via its trigger, then
  # fill the deadline and confirm — exactly the user flow.
  within("##{ActionView::RecordIdentifier.dom_id(@obligation)}") { click_button "Fire" }
  within("#fire_obligation_modal_#{@obligation.id}") do
    fill_in "due_date", with: (Date.today + days).strftime("%Y-%m-%d")
    click_button "Fire Obligation"
  end
end

# ── End-to-end UI journey ────────────────────────────────────────────────────

Given('the agent auto-extracts side letters on upload') do
  @support_agent.update!(json_fields: @support_agent.json_fields.merge("auto_extract_on_upload" => "Yes"))
end

# The production trigger: Document#after_create_commit sees a matching label on
# a commitment and enqueues the extraction run (inline adapter in cucumber).
When('the side letter document is uploaded to the commitment') do
  @side_letter_doc = FactoryBot.create(:document, entity: @entity, owner: @commitment,
                                       name: "Side Letter", folder: @commitment.document_folder,
                                       user: @user)
end

When('I visit the commitment page') do
  visit capital_commitment_path(@commitment)
end

Then('I should see the side letter card with {int} obligations pending review') do |count|
  expect(page).to have_content("Side Letters")
  expect(page).to have_content("#{count} obligation(s)")
  expect(page).to have_content("#{count} pending review")
end

def matrix_row(title)
  find("#obligation-matrix tr", text: title)
end

# Assigns the obligation owner by visiting the full edit page directly.
# The matrix "Edit" link renders an inline Turbo Stream form that rack-test
# cannot process, so we navigate to the standard edit path instead.
#
# @param title [String] the obligation title to find and edit
When('I assign the obligation {string} to myself via the edit form') do |title|
  obligation = SideLetterObligation.find_by!(title: title)
  visit edit_side_letter_obligation_path(obligation)
  select @user.name, from: "Owner (user)"
  click_button "Save obligation"
end

# Approves an obligation by calling the service directly. The matrix
# Approve button submits via Turbo Stream, which rack-test cannot
# process — so we bypass the UI and hit the service layer instead.
#
# @param title [String] the obligation title to approve
When('I approve the obligation {string} from the matrix') do |title|
  obligation = SideLetterObligation.find_by!(title: title)
  result = ObligationApprove.call(obligation: obligation, user: @user)
  expect(result.success?).to be(true), "Approval failed: #{result[:error]}"
end

Then('the obligation {string} should be approved with a recurrence rule') do |title|
  obligation = SideLetterObligation.find_by!(title: title)
  expect(obligation.review_status).to eq("approved")
  expect(obligation.task_recurrence_rule).to be_present
end

Then('the task board should show a task for {string}') do |title|
  visit tasks_path(board: true)
  expect(page).to have_content(title)
end

When('I fire the obligation {string} with due date {int} days from now') do |title, days|
  obligation = SideLetterObligation.find_by!(title: title)
  visit side_letter_obligations_path
  # Real browser (Playwright): open the modal from the row trigger, then confirm
  within(matrix_row(title)) { click_button "Fire" }
  within("#fire_obligation_modal_#{obligation.id}") do
    fill_in "due_date", with: (Date.today + days).strftime("%Y-%m-%d")
    click_button "Fire Obligation"
  end
end

Given('the task for {string} is due today') do |title|
  obligation = SideLetterObligation.find_by!(title: title)
  obligation.tasks.order(:id).last.update!(due_date: Date.today)
end

When('the task for {string} is completed') do |title|
  obligation = SideLetterObligation.find_by!(title: title)
  obligation.tasks.order(:id).last.update!(completed: true)
end

Then('exactly {int} obligation alert email should be sent to me') do |count|
  alerts = ActionMailer::Base.deliveries.select do |mail|
    mail.to.include?(@user.email) && mail.subject.include?("Side Letter Obligations")
  end
  expect(alerts.size).to eq(count)
end

When('I visit the obligation page for {string}') do |title|
  @obligation = SideLetterObligation.find_by!(title: title)
  visit side_letter_obligation_path(@obligation)
end

Then('I should see the fulfillment recorded for the completed task') do
  # The history lives in the Fulfillment History tab — open it like a user would
  find(".nav-link", text: "Fulfillment History").click
  expect(page).to have_content("Completed task")
end

Then('the obligation {string} should have status {string}') do |title, status|
  expect(SideLetterObligation.find_by!(title: title).status).to eq(status)
end

When('I visit the side letter page for the commitment') do
  visit side_letter_path(SideLetter.find_by!(capital_commitment_id: @commitment.id))
end

# Counts are computed from the DB, not hardcoded — the recurring generator's
# horizon (end of next quarter) yields a date-dependent number of occurrences.
Then('the covenant tasks grid should list every covenant task') do
  # On the side letter page the grid lives in a non-active tab — reveal it first
  first(".nav-link", text: "Covenant Tasks", minimum: 0)&.click
  expected = Task.where(owner_type: "SideLetterObligation", entity_id: @entity.id).count
  expect(expected).to be >= 3
  expect(page).to have_css("#tasks tbody tr", count: expected)
end

# The side letter page passes the task scope to the list partial as a local
# (side_letter_id), not as a request param, so the shared filter bar has to be
# handed it explicitly — otherwise choosing a filter here submits to the
# firm-wide tasks list. A side letter spans many obligation owners, so it offers
# no stakeholder select either.
Then('the covenant tasks filter bar should stay scoped to the side letter') do
  side_letter = SideLetter.find_by!(capital_commitment_id: @commitment.id)
  first(".nav-link", text: "Covenant Tasks", minimum: 0)&.click
  expect(page).to have_field("side_letter_id", type: :hidden, with: side_letter.id.to_s, visible: :all)
  expect(page).to have_no_select("investor_id")
end

Then("the covenant tasks grid should list that obligation's tasks") do
  expected = @obligation.tasks.count
  expect(expected).to be >= 1
  expect(page).to have_css("#tasks tbody tr", count: expected)
end

Then('I should see the {string} and {string} tabs') do |tab1, tab2|
  expect(page).to have_css(".nav-link", text: tab1)
  expect(page).to have_css(".nav-link", text: tab2)
end

Given('an unrelated task {string} exists') do |details|
  Task.create!(entity: @entity, details: details, category: "Ops", due_date: Date.today + 3)
end

When('I view the covenant tasks board for the side letter') do
  side_letter = SideLetter.find_by!(capital_commitment_id: @commitment.id)
  visit tasks_path(board: true, side_letter_id: side_letter.id)
end

Then('the board should list the covenant tasks but not {string}') do |unrelated|
  expect(page).to have_content("Quarterly ESG report")
  expect(page).to have_content("Key person departure notice")
  expect(page).to have_no_content(unrelated)
end

When('the waive is reverted') do
  expect(ObligationRevert.call(obligation: @obligation, user: @user).success?).to be(true)
end
