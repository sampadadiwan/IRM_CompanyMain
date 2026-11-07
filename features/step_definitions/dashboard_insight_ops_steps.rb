# Steps for features/core/dashboard_insight_investor_widgets.feature, features/core/dashboard_insight_ops_widgets.feature
# and features/security/dashboard_insight_ops_isolation.feature — the Investor Pending Actions, Side-letter
# Obligations, Needs Attention, Overdue Tasks by Assignee and Stuck Workflows insight widgets.
# Worked examples H17–H24, E45–E63, X3, X10, X11 — openspec/changes/dashboard-insight-widgets/business-rules.md#6 and #7
# Records are built directly (update_columns after create) so each row's figures are exactly what the scenario names.

module DashboardInsightOpsSteps
  LAKH = 100_000

  def ops_insight_funds
    @ops_insight_funds ||= {}
  end

  def ops_insight_fund(name)
    ops_insight_funds[name] ||= FactoryBot.create(:fund, name:, entity: @entity, currency: "INR", unit_types: "A")
  end

  # An LP of the signed-in firm (category Investor, so its page is the Investor Dashboard)
  def ops_insight_lp(name)
    @ops_insight_lps ||= {}
    @ops_insight_lps[name] ||= begin
      investor_entity = FactoryBot.create(:entity, name:, entity_type: "Investor")
      FactoryBot.create(:investor, entity: @entity, investor_entity:, investor_name: name, category: "LP",
                                   primary_email: investor_entity.primary_email)
    end
  end

  def ops_insight_commitment(lp_name, fund_name)
    @ops_insight_commitments ||= {}
    @ops_insight_commitments[[lp_name, fund_name]] ||= begin
      fund = ops_insight_fund(fund_name)
      cc = FactoryBot.create(:capital_commitment, fund:, entity: @entity, investor: ops_insight_lp(lp_name), unit_type: "A",
                                                  folio_id: "F#{SecureRandom.hex(3)}", folio_currency: "INR",
                                                  folio_committed_amount_cents: 500 * LAKH * 100)
      cc.update_columns(committed_amount_cents: 500 * LAKH * 100, other_fee_cents: 0)
      cc
    end
  end

  # A remittance owing `lakh` lakh on a call due `due_date`, with the exact status named
  def ops_insight_remittance!(lp_name, fund_name, call_name, lakh, due_date, status)
    cc = ops_insight_commitment(lp_name, fund_name)
    call = FactoryBot.create(:capital_call, fund: cc.fund, entity: @entity, name: call_name, call_basis: "Upload",
                                            due_date:, call_date: due_date - 30.days)
    rem = FactoryBot.create(:capital_remittance, capital_call: call, fund: cc.fund, entity: @entity, investor: cc.investor,
                                                 capital_commitment: cc, folio_id: cc.folio_id,
                                                 folio_committed_amount_cents: cc.committed_amount_cents,
                                                 committed_amount_cents: cc.committed_amount_cents)
    rem.update_columns(call_amount_cents: lakh * LAKH * 100, collected_amount_cents: 0, other_fee_cents: 0, status:,
                       verified: status != "Pending")
    rem
  end

  # A user of the signed-in firm, created on first mention by first name
  def ops_insight_user(first_name)
    return @user if first_name == @user.first_name

    @ops_insight_users ||= {}
    @ops_insight_users[first_name] ||= FactoryBot.create(:user, entity: @entity, first_name:, last_name: "Ops")
  end

  def ops_insight_task!(entity:, due_date:, assigned_to: nil, owner: entity, user: @user)
    Task.create!(entity:, for_entity: entity, owner:, user:, details: "Insight task #{SecureRandom.hex(3)}",
                 due_date:, completed: false, assigned_to:)
  end

  def ops_insight_widget(name)
    find("[data-insight-widget='#{name.parameterize}']")
  end

  # Runs the list a Needs Attention card links to, as the signed-in user, the way its index action does (H21)
  def ops_insight_list_count(path, user)
    uri = URI(path)
    params = ActionController::Parameters.new(Rack::Utils.parse_nested_query(uri.query))
    scope = ->(relation) { Pundit.policy_scope!(user, relation) }
    case uri.path
    when "/tasks" then TaskList.call(user, params) { |r| scope.call(r) }.tasks.count
    when "/investor_kycs" then InvestorKycList.call(user, params) { |r| scope.call(r) }.investor_kycs.count
    when "/capital_remittances" then CapitalRemittanceList.call(user, params) { |r| scope.call(r) }.capital_remittances.count
    when "/documents" then scope.call(Document.ransack(params[:q]&.to_unsafe_h).result).count
    else raise "No list counter for #{uri.path}"
    end
  end

  def ops_insight_viewer
    @ops_insight_viewer || @user
  end
end
World(DashboardInsightOpsSteps)

# ── Setup ────────────────────────────────────────────────────────────────────────────────────

Given('the ops insight fund {string} exists') do |name|
  ops_insight_fund(name)
end

Given('the ops insight LP {string} has a commitment in {string}') do |lp_name, fund_name|
  ops_insight_commitment(lp_name, fund_name)
end

Given('the ops insight LP {string} owes {int} lakh on call {string} in {string} due {string} with status {string}') do |lp_name, lakh, call_name, fund_name, due, status|
  ops_insight_remittance!(lp_name, fund_name, call_name, lakh, Date.parse(due), status)
end

# status: not_sent / link_sent / completed (submitted, not verified) / verified
Given('the ops insight LP {string} has a KYC {string} with status {string} expiring {string}') do |lp_name, full_name, status, expiry|
  kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor: ops_insight_lp(lp_name), full_name:)
  kyc.update_columns(submission_status: status, verified: status == "verified", completed_by_investor: status == "completed",
                     expiry_date: Date.parse(expiry))
end

# published: the approval has been sent to investors (approved); a Pending response awaits this LP
Given('the ops insight LP {string} has an approval {string} due {string} that is {string}') do |lp_name, title, due, state|
  lp = ops_insight_lp(lp_name)
  approval = FactoryBot.create(:approval, entity: @entity, title:, due_date: Date.parse(due))
  approval.update_columns(approved: state == "published")
  ApprovalResponse.insert!({ entity_id: @entity.id, approval_id: approval.id, investor_id: lp.id,
                             response_entity_id: lp.investor_entity_id, status: "Pending",
                             created_at: Time.current, updated_at: Time.current })
end

Given('the ops insight LP {string} has a document {string} in {string} with e-sign status {string}') do |lp_name, name, fund_name, status|
  cc = ops_insight_commitment(lp_name, fund_name)
  doc = FactoryBot.create(:document, name:, entity: @entity, owner: cc, folder: cc.document_folder, user: @user)
  doc.update_columns(sent_for_esign: true, esign_status: status, sent_for_esign_date: Time.zone.today - 3.days)
end

# The review is approved or pending_review; the status is active, fulfilled or waived (nil while unreviewed)
Given('the ops insight LP {string} has a side-letter obligation {string} in {string} due {string} with status {string} and review {string}') do |lp_name, title, fund_name, due, status, review|
  # The side-letter policies keep the feature dark unless the firm switched the agent on
  @entity.support_agents.set!(:side_letter_obligation_agent)
  @entity.save!
  cc = ops_insight_commitment(lp_name, fund_name)
  @ops_insight_side_letters ||= {}
  side_letter = @ops_insight_side_letters[cc.id] ||= begin
    doc = FactoryBot.create(:document, entity: @entity, owner: cc, name: "Side Letter", folder: cc.document_folder, user: @user)
    SideLetter.create!(entity: @entity, capital_commitment: cc, document: doc)
  end
  obligation = side_letter.side_letter_obligations.create!(entity: @entity, obligation_type: "reporting", title:,
                                                           trigger_type: "one_time", review_status: "pending_review",
                                                           extracted_by: "manual", reminder_days_before: 7)
  obligation.update_columns(review_status: review, status: review == "approved" ? status : nil,
                            next_due_date: Date.parse(due), owner_user_id: @user.id)
end

# assignee: a first name, or "nobody" for an unassigned task
Given('there are {int} ops insight open tasks due {string} for {string}') do |count, due, assignee|
  assigned_to = assignee == "nobody" ? nil : ops_insight_user(assignee)
  count.times { ops_insight_task!(entity: @entity, due_date: Date.parse(due), assigned_to:) }
end

Given('{int} more ops insight people each have an overdue task') do |count|
  count.times { |i| ops_insight_task!(entity: @entity, due_date: Time.zone.today - 5.days, assigned_to: ops_insight_user("Person#{i + 1}")) }
end

# status: active / complete / archived
Given('there is an ops insight journey on the call {string} in {string} at step {string} since {string} with status {string}') do |call_name, fund_name, step, since, status|
  fund = ops_insight_fund(fund_name)
  call = CapitalCall.find_by(fund:, name: call_name) ||
         FactoryBot.create(:capital_call, fund:, entity: @entity, name: call_name, call_basis: "Upload",
                                          due_date: Time.zone.today + 10.days, call_date: Time.zone.today)
  @ops_insight_template ||= WorkflowTemplate.create!(entity: @entity, name: "Capital call journey", workflowable_type: "CapitalCall")
  WorkflowInstance.create!(workflowable: call, workflow_template: @ops_insight_template, entity_id: @entity.id, status:,
                           template_snapshot: { name: "Capital call journey", steps: [{ name: step, position: 1 }] },
                           current_step_position: 1, current_step_since: Time.zone.parse("#{since} 10:00"))
end

Given('another firm has an overdue ops insight task') do
  other = FactoryBot.create(:entity, entity_type: "Investment Fund", name: "Other Capital")
  other_user = FactoryBot.create(:user, entity: other)
  ops_insight_task!(entity: other, due_date: Time.zone.today - 3.days, user: other_user, assigned_to: other_user)
end

# An employee (not a company admin) who may read investors and is given access to one fund only (X10, X11)
Given('the ops insight employee {string} can access only the fund {string}') do |first_name, fund_name|
  employee = ops_insight_user(first_name)
  employee.remove_role(:company_admin)
  employee.add_role(:employee)
  employee.extended_permissions.set(:investor_read)
  employee.save!
  AccessRight.create!(owner: ops_insight_fund(fund_name), entity_id: @entity.id, user_id: employee.id, notify: false)
end

Given('I sign in as the ops insight employee {string}') do |first_name|
  @ops_insight_viewer = ops_insight_user(first_name)
  Warden.test_mode!
  Object.new.extend(Warden::Test::Helpers).login_as(@ops_insight_viewer, scope: :user)
end

# ── Opening the pages ────────────────────────────────────────────────────────────────────────

When('I open the Ops Dashboard for the ops insight widgets') do
  visit(dashboard_dashboard_widgets_path(dashboard_name: DashboardWidget::OPS_DASHBOARD))
end

When('I open the investor dashboard of {string} for the ops insight widgets') do |lp_name|
  visit(dashboard_investor_path(ops_insight_lp(lp_name)))
end

When('I open my home page for the ops insight widgets') do
  visit("/entities/dashboard")
end

# ── Checks ───────────────────────────────────────────────────────────────────────────────────

Then('the ops insight cards should show:') do |table|
  shown = all("[data-insight-card]").to_h { |card| [card["data-insight-card"], card.find("[data-insight-count]").text.strip] }
  expect(shown).to eq(table.raw.to_h)
end

Then('the ops insight card {string} should show {int}') do |subtitle, count|
  expect(find("[data-insight-card='#{subtitle}'] [data-insight-count]").text.strip).to eq(count.to_s)
end

# H21 — the card's link really filters: following it opens the list, and that list holds the counted rows
Then('the list behind the ops insight card {string} should hold {int} records') do |subtitle, count|
  path = find("[data-insight-card='#{subtitle}']")[:href]
  expect(ops_insight_list_count(path, ops_insight_viewer)).to eq(count)
  find("[data-insight-card='#{subtitle}']").click
  expect(page).to have_current_path(URI(path).path, ignore_query: true)
end

Then('the ops insight widget {string} should say {string}') do |name, message|
  expect(ops_insight_widget(name).find("[data-insight-empty-state]")).to have_text(message)
end

Then('the ops insight widget {string} should list {string}') do |name, rows|
  shown = ops_insight_widget(name).all("[data-insight-row]").pluck("data-insight-row")
  expect(shown).to eq(rows.split(",").map(&:strip))
end

Then('the ops insight widget {string} row {string} should show {string}') do |name, row, text|
  expect(ops_insight_widget(name).find("[data-insight-row='#{row}'] [data-insight-value]")).to have_text(text)
end

Then('the ops insight widget {string} should not list {string}') do |name, row|
  expect(ops_insight_widget(name)).to have_no_css("[data-insight-row='#{row}']")
end

Then('the ops insight widget {string} should not be rendered') do |name|
  expect(page).to have_no_css("[data-insight-widget='#{name.parameterize}']")
end

Then('the ops insight section {string} should count {int}') do |section, count|
  within(ops_insight_widget("Investor Pending Actions")) do
    expect(find("[data-insight-section='#{section}'] [data-insight-count]").text.strip).to eq(count.to_s)
  end
end

Then('the ops insight section {string} should list {string}') do |section, rows|
  within(ops_insight_widget("Investor Pending Actions")) do
    shown = find("[data-insight-section='#{section}']").all("[data-insight-row]").pluck("data-insight-row")
    expect(shown).to eq(rows.split(",").map(&:strip))
  end
end

Then('the ops insight section {string} row {string} should show {string}') do |section, row, text|
  within(ops_insight_widget("Investor Pending Actions")) do
    expect(find("[data-insight-section='#{section}'] [data-insight-row='#{row}'] [data-insight-value]")).to have_text(text)
  end
end
