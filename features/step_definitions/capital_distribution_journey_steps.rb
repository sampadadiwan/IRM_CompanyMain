# Steps for the capital distribution journey and the distribution fixes that ship with it.
# Worked examples in openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples

# ── Distribution page ─────────────────────────────────────────────────────────

When("I open the capital distribution page") do
  visit capital_distribution_path(@capital_distribution)
  expect(page).to have_css("#capital_distribution_#{@capital_distribution.id}_actions")
end

When("I open the distribution's Actions menu") do
  within("#capital_distribution_#{@capital_distribution.id}_actions") { click_on("Actions") }
end

Then("the distribution's Actions menu should not offer {string}") do |label|
  within("#capital_distribution_#{@capital_distribution.id}_actions .dropdown-menu") do
    expect(page).to have_no_button(label)
  end
end

When("I click {string} in the distribution's Actions menu and confirm") do |label|
  within("#capital_distribution_#{@capital_distribution.id}_actions .dropdown-menu") { click_on(label) }
  within("#confirmModal") { click_on("Proceed") }
end

# Posts the member action the way a hand-crafted request would, bypassing the menu (X1, X2):
# a real form (with the page's CSRF token when there is one), so only the policy can stop it.
When("I send the distribution {string} request directly") do |action|
  method = action == "approve" ? "post" : "patch"
  path = "/capital_distributions/#{@capital_distribution.id}/#{action}"
  page.execute_script(<<~JS)
    const form = document.createElement("form");
    form.method = "post"; form.action = "#{path}"; form.dataset.turbo = "false";
    const add = (name, value) => { const i = document.createElement("input"); i.type = "hidden"; i.name = name; i.value = value; form.appendChild(i); };
    add("_method", "#{method}");
    const csrf = document.querySelector("meta[name='csrf-token']"); // absent when forgery protection is off (test)
    if (csrf) add("authenticity_token", csrf.content);
    document.body.appendChild(form); form.submit();
  JS
end

Then("the distribution should not be approved") do
  expect(@capital_distribution.reload.approved).to be(false)
end

Then("the distribution should be approved by me") do
  expect(page).to have_text("approved")
  @capital_distribution.reload
  expect(@capital_distribution.approved).to be(true)
  expect(@capital_distribution.approved_by_user_id).to eq(@user.id)
end

Then("no payment of the distribution should be completed") do
  payments = @capital_distribution.capital_distribution_payments
  expect(payments.count).to be_positive
  expect(payments.where(completed: true).count).to eq(0)
end

Then("every payment of the distribution should be completed") do
  expect(page).to have_text("marked as completed")
  payments = @capital_distribution.capital_distribution_payments
  expect(payments.count).to be_positive
  expect(payments.where(completed: false).count).to eq(0)
end

# ── Form (E23) ────────────────────────────────────────────────────────────────

When("I open the new capital distribution form") do
  visit new_capital_distribution_path('capital_distribution[fund_id]': @fund.id)
  expect(page).to have_field("capital_distribution_title")
end

Then("the page should not mention {string}") do |text|
  expect(page).to have_no_text(text)
end

# ── Jobs (X4, X5) ─────────────────────────────────────────────────────────────

# The model enqueues generation with no user (after_create_commit). The payment create service is
# made to fail for one commitment so the job takes its error-reporting path with user_id nil.
When("payment generation for the distribution hits an error with no user") do
  @capital_distribution.capital_distribution_payments.destroy_all
  failed = Class.new { def success? = false }.new
  # Overridden on this class only, and removed again so the inherited Operation.call comes back
  CapitalDistributionPaymentCreate.define_singleton_method(:call) do |capital_distribution_payment:, **|
    capital_distribution_payment.errors.add(:base, "Investor kyc must exist")
    failed
  end
  begin
    CapitalDistributionJob.perform_now(@capital_distribution.id)
    @job_error = nil
  rescue StandardError => e
    @job_error = e
  ensure
    CapitalDistributionPaymentCreate.singleton_class.remove_method(:call)
  end
end

Then("the payment generation job should finish without raising") do
  expect(@job_error).to be_nil
  expect(@capital_distribution.capital_distribution_payments.count).to eq(0)
end

When("the distribution's fees are recomputed by me") do
  @recompute_messages = []
  messages = @recompute_messages
  job = CapitalDistributionPaymentRecomputeFeesJob.new
  job.define_singleton_method(:send_notification) { |message, *_args| messages << message }
  job.perform(@capital_distribution.id, @user.id)
end

Then("the first recompute message should be {string}") do |message|
  expect(@recompute_messages.first).to eq(message)
end

# ── Seeding and launch (capital_distribution_journey*.feature) ────────────────

DISTRIBUTION_JOURNEY_KEYS = [CapitalDistributionJourneySetup::FULL_KEY, CapitalDistributionJourneySetup::LIGHT_KEY].freeze

Given("the entity's capital distribution journeys are seeded") do
  CapitalDistributionJourneySetup.call(entity: @entity)
end

# Entities are set up with the journeys on create (SetupCompany); this takes them away again
Given("the entity's capital distribution journeys are removed") do
  WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "CapitalDistribution").destroy_all
  WorkflowTemplate.where(entity: @entity, system_key: DISTRIBUTION_JOURNEY_KEYS)
                  .find_each { |t| t.workflow_assignments.destroy_all && t.destroy }
end

When("an imported capital distribution {string} is created") do |args|
  @capital_distribution = FactoryBot.build(:capital_distribution, entity: @fund.entity, fund: @fund, manual_generation: true)
  key_values(@capital_distribution, args)
  @capital_distribution.save!
end

Then("the distribution has the {string} journey") do |template_name|
  instance = @capital_distribution.reload.workflow_instances.where(evaluated: true).last
  expect(instance&.template_name).to eq(template_name)
end

Then("the distribution has no journey") do
  expect(@capital_distribution.reload.workflow_instances).not_to exist
end

# ── Evaluation and assertions ─────────────────────────────────────────────────

When("the distribution's journey is evaluated") do
  @journey_record = @capital_distribution.reload
  WorkflowEvaluator.for(@journey_record, cause: :progress)
end

# Table columns: task | status | message (a blank message is not checked)
Then("the distribution's journey should show:") do |table|
  instance = journey_instance(@capital_distribution)
  table.hashes.each do |row|
    result = instance.step_result(journey_position(instance, row["task"].strip)) || {}
    expect(result["status"]).to eq(row["status"]), "#{row['task']}: #{result.inspect}"
    expect(result["message"]).to eq(row["message"].strip) if row["message"].present?
  end
end

Then("the distribution's journey current task should be {string}") do |task|
  instance = journey_instance(@capital_distribution)
  expect(instance.current_step_position).to eq(journey_position(instance, task)), instance.step_results.inspect
end

Then("the distribution's journey should have the tasks {string}") do |names|
  instance = journey_instance(@capital_distribution)
  expect(instance.snapshot_steps.pluck(:name)).to eq(names.split(",").map(&:strip))
end

# ── Data set-up for the checks ───────────────────────────────────────────────

Given("every commitment of the fund is set to skip doc gen") do
  CapitalCommitment.where(fund_id: @fund.id).find_each do |commitment|
    commitment.update_column(:json_fields, (commitment.json_fields || {}).merge("skip_doc_gen" => "Yes"))
  end
end

Given("the distribution has no unit prices") do
  @capital_distribution.update_column(:unit_prices, {})
end

# A finished upload with errors that created this distribution's payments (E4). Inserted directly:
# the check reads only status and row counts, and a real upload would need a spreadsheet.
When("a payment upload for the distribution has failed") do
  now = Time.current
  upload_id = ImportUpload.insert!({ entity_id: @entity.id, owner_type: "CapitalDistribution", owner_id: @capital_distribution.id,
                                     user_id: @user.id, name: "Distribution payments", import_type: "CapitalDistributionPayment",
                                     status: "Failed", total_rows_count: 3, processed_row_count: 3, created_at: now, updated_at: now }).rows.first&.first
  upload_id ||= ImportUpload.where(owner: @capital_distribution).order(:id).last.id
  commitment = CapitalCommitment.where(fund_id: @fund.id).order(:id).first
  payment = CapitalDistributionPayment.new(fund: @fund, entity: @entity, capital_distribution: @capital_distribution,
                                           capital_commitment: commitment, folio_id: commitment.folio_id, investor: commitment.investor, income_cents: 100_000,
                                           payment_date: @capital_distribution.distribution_date, import_upload_id: upload_id)
  CapitalDistributionPaymentCreate.call(capital_distribution_payment: payment)
  expect(payment).to be_persisted, payment.errors.full_messages.inspect
end

Given("the KYC of {int} investor in the distribution is not verified") do |count|
  @capital_distribution.capital_distribution_payments.order(:id).first(count).each do |payment|
    payment.capital_commitment.investor_kyc.update_columns(verified: false)
  end
end

# What the notice job produces: one Generated document per emailable payment whose KYC is verified
def create_distribution_notice(payment, approved: false)
  Document.create!(entity_id: payment.entity_id, owner: payment, name: "Distribution Notice - #{payment.id}",
                   owner_tag: "Generated", file: File.open(SAMPLE_NOTICE_PDF, "rb"), user_id: @user.id, approved:,
                   from_template_id: @distribution_template&.id)
end

When("the distribution's notices are generated for investors with verified KYC") do
  @capital_distribution.capital_distribution_payments.includes(capital_commitment: :investor_kyc).find_each do |payment|
    create_distribution_notice(payment) if payment.capital_commitment.investor_kyc&.verified
  end
end

Then("the page should not show a journey") do
  expect(page).to have_css("#capital_distribution_#{@capital_distribution.id}_actions")
  expect(page).to have_no_css("#capital_distribution_journey_card")
end

# ── Rollout (capital_distribution_journey_rollout.feature) ───────────────────

When("I run the distribution journey rollout for the entity") do
  run_journey_rollout(execute: false, task_name: "capital_distribution_journeys:rollout")
end

When("I run the distribution journey rollout for the entity with EXECUTE") do
  run_journey_rollout(execute: true, task_name: "capital_distribution_journeys:rollout")
end

Then("the entity should have no capital distribution journeys") do
  expect(WorkflowTemplate.where(entity: @entity, system_key: DISTRIBUTION_JOURNEY_KEYS)).not_to exist
  expect(WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "CapitalDistribution")).not_to exist
end

def expect_distribution_journeys(entity, full, light)
  expect(WorkflowTemplate.find_by!(entity:, system_key: CapitalDistributionJourneySetup::FULL_KEY).workflow_steps.count).to eq(full)
  expect(WorkflowTemplate.find_by!(entity:, system_key: CapitalDistributionJourneySetup::LIGHT_KEY).workflow_steps.count).to eq(light)
end

Then("the entity should have the Full distribution journey with {int} tasks and the Light one with {int} tasks") do |full, light|
  expect_distribution_journeys(@entity, full, light)
end

Then("imported distributions should go to Light and other distributions to Full") do
  rules = WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "CapitalDistribution").order(:priority).to_a
  expect(rules.map { |r| r.workflow_template.system_key }).to eq(DISTRIBUTION_JOURNEY_KEYS.reverse)
  expect(rules.first.conditions).to eq([{ "attribute" => "manual_generation", "operator" => "eq", "value" => "true" }])
  expect(rules.all?(&:auto_launch)).to be(true)
end

# Entity creation runs SetupCompany, which now seeds the distribution journeys too
When("a new fund company is created") do
  @new_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
end

Then("the new company should have the Full distribution journey with {int} tasks and the Light one with {int} tasks") do |full, light|
  expect_distribution_journeys(@new_entity, full, light)
end

Given("the Full distribution journey has a {string} approval step before {string}") do |name, before|
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: CapitalDistributionJourneySetup::FULL_KEY)
  # The seeded Full journey already has a CFO sign-off with no approver: pick the user on it
  if (seeded = template.workflow_steps.find_by(name:))
    seeded.workflow_step_actors.create!(user: @user)
    next
  end
  target = template.workflow_steps.find_by!(name: before).position
  # Shift from the bottom up so the unique (template, position) index never collides
  template.workflow_steps.where(position: target..).reorder(position: :desc).each { |s| s.update_column(:position, s.position + 1) }
  step = template.workflow_steps.create!(position: target, name:, kind: "human", states: "Approved,Rejected",
                                         quorum_rule: "any_one", on_reject_rule: "previous_step")
  step.workflow_step_actors.create!(user: @user)
end

Then("the entity should have exactly {int} Full and {int} Light distribution journey") do |full, light|
  expect(WorkflowTemplate.where(entity: @entity, system_key: CapitalDistributionJourneySetup::FULL_KEY).count).to eq(full)
  expect(WorkflowTemplate.where(entity: @entity, system_key: CapitalDistributionJourneySetup::LIGHT_KEY).count).to eq(light)
end

Then("the Full distribution journey should still have a {string} step") do |name|
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: CapitalDistributionJourneySetup::FULL_KEY)
  expect(template.workflow_steps.where(name:)).to exist
end

Then("the entity should have exactly {int} capital distribution auto-assignment rules") do |count|
  expect(WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "CapitalDistribution").count).to eq(count)
end

# X3 — posts the setup the way a hand-crafted request would, from the Workflow Templates page
When("I send the {string} journey setup request directly") do |kind|
  page.execute_script(<<~JS)
    const form = document.createElement("form");
    form.method = "post"; form.action = "/workflow_templates/setup_journeys?kind=#{kind}"; form.dataset.turbo = "false";
    const csrf = document.querySelector("meta[name='csrf-token']");
    if (csrf) { const i = document.createElement("input"); i.type = "hidden"; i.name = "authenticity_token"; i.value = csrf.content; form.appendChild(i); }
    document.body.appendChild(form); form.submit();
  JS
end

# ── Distribution page (capital_distribution_journey_ui.feature) ──────────────

When("I open the distribution's journey page") do
  visit capital_distribution_path(@capital_distribution)
  expect(page).to have_css("#capital_distribution_journey_card")
end

# The same page, without waiting for a visible card: a complete journey renders its card hidden
# (workflow_instances/_journey_panel), and the breadcrumb's journey icon is what brings it back
When("I open the distribution page") do
  visit capital_distribution_path(@capital_distribution)
  # The breadcrumb names the distribution (CapitalDistributionsController#set_capital_distribution),
  # so this waits for the page without touching the journey card either way
  expect(page).to have_css(".breadcrumbs", text: @capital_distribution.to_s)
end

# Backdating the instance, as an old journey on a long-settled distribution would be. The evaluator
# writes completed_at once and never rewrites it, so re-evaluating on page load leaves this alone.
Given("the distribution's journey was completed {int} days ago") do |days|
  instance = journey_instance(@capital_distribution)
  expect(instance.instance_complete?).to be(true), instance.step_results.inspect
  instance.update_columns(completed_at: days.days.ago)
end

Given("the distribution's notices are generated and {int} of them is approved") do |approved_count|
  @capital_distribution.capital_distribution_payments.order(:id).each_with_index do |payment, idx|
    create_distribution_notice(payment, approved: idx < approved_count)
  end
end

# Both acknowledge steps confirmed by the logged-in user, as Mark reviewed does (H5)
Given("both distribution review tasks are marked reviewed") do
  @journey_record = @capital_distribution.reload # read by the engine's history / vote steps
  WorkflowEvaluator.for(@journey_record, cause: :progress)
  ["Review email", "Check preview"].each do |task|
    instance = journey_instance(@capital_distribution)
    result = WorkflowAcknowledge.call(instance:, step_position: journey_position(instance, task), user: @user)
    expect(result.success?).to be(true), "#{task}: #{result[:errors]} #{instance.step_results.inspect}"
  end
end

# The panel's button opens the Actions menu and clicks the control, whose own confirm dialog appears
When("I click the panel action and proceed") do
  find("#journey_action").click
  within("#confirmModal") { click_on("Proceed") }
end

Given("{int} commitment of the distribution is set to skip doc gen") do |count|
  @capital_distribution.capital_distribution_payments.order(:id).first(count).each do |payment|
    commitment = payment.capital_commitment
    commitment.update_column(:json_fields, (commitment.json_fields || {}).merge("skip_doc_gen" => "Yes"))
  end
end

Given("{int} investor of the distribution has nobody subscribed to Distribution emails") do |count|
  @capital_distribution.capital_distribution_payments.order(:id).last(count).each do |payment|
    InvestorAccess.where(investor_id: payment.investor_id).update_all(approved: false)
  end
end

Given("the distribution's investors have been emailed") do
  @capital_distribution.capital_distribution_payments.update_all(completed: true, notification_sent: true)
end

# A notice on a different distribution of the same fund, which the link must leave out (E22)
Given("another distribution of the fund has an unapproved notice") do
  other = FactoryBot.build(:capital_distribution, entity: @fund.entity, fund: @fund, title: "Other Distribution", approved: false)
  other.save!
  payment = other.capital_distribution_payments.first || raise("no payments generated for the other distribution")
  create_distribution_notice(payment)
end

Then("{string} should open a new window listing {int} notices with the approval hint") do |label, count|
  link = find("#capital_distribution_view_notices_to_approve_btn", text: label)
  new_window = window_opened_by { link.click }
  within_window(new_window) do
    expect(page).to have_current_path(/documents/)
    expect(page).to have_text("These notices still need approval")
    # One row per notice: this distribution's two unapproved ones, not the other distribution's
    expect(page).to have_css("tr", text: /Distribution Notice - \d+/, count:)
    other_ids = Document.where(owner_tag: "Generated").where.not(owner_id: @capital_distribution.capital_distribution_payment_ids).pluck(:owner_id)
    other_ids.each { |id| expect(page).to have_no_text("Distribution Notice - #{id}") }
  end
  new_window.close
end

Then("the distribution page should still be open in the original window") do
  expect(page).to have_current_path(capital_distribution_path(@capital_distribution))
  expect(page).to have_css("#journey_step_bar")
end

# Moves the distribution (and its fund) to a different company, so the logged-in user is an outsider
Given("the distribution belongs to another company") do
  other = FactoryBot.create(:entity, entity_type: "Investment Fund")
  @capital_distribution.update_columns(entity_id: other.id)
end

When("I load the distribution's journey panel directly") do
  visit journey_capital_distribution_path(@capital_distribution)
end

# ── Hooks (capital_distribution_journey.feature, phase 5) ────────────────────

# Records each journey re-check and each "tell open pages" broadcast for distributions, still running
# the real methods. Its own module (not the call's JourneyActivitySpy): ids of calls and
# distributions would otherwise mix.
module DistributionJourneyActivitySpy
  mattr_accessor :rechecked, :broadcast, default: []

  def journey_progress!(...)
    DistributionJourneyActivitySpy.rechecked += [id]
    super
  end

  def broadcast_journey_change
    DistributionJourneyActivitySpy.broadcast += [id]
    super
  end
end
CapitalDistribution.prepend(DistributionJourneyActivitySpy) unless CapitalDistribution <= DistributionJourneyActivitySpy

Given("journey activity on distributions is recorded") do
  DistributionJourneyActivitySpy.rechecked = []
  DistributionJourneyActivitySpy.broadcast = []
end

Then("the distribution's journey should have been re-checked") do
  expect(DistributionJourneyActivitySpy.rechecked).to include(@capital_distribution.id)
end

Then("the distribution's journey should have been re-checked once") do
  expect(DistributionJourneyActivitySpy.rechecked.count(@capital_distribution.id)).to eq(1)
end

Then("the distribution's journey should not have been re-checked") do
  expect(DistributionJourneyActivitySpy.rechecked).not_to include(@capital_distribution.id)
end

Then("open pages for the distribution should have been told about the change") do
  expect(DistributionJourneyActivitySpy.broadcast).to include(@capital_distribution.id)
end

Then("the distribution's journey should be complete") do
  instance = journey_instance(@capital_distribution)
  expect(instance.instance_complete?).to be(true), instance.step_results.inspect
end

Then("the distribution's journey message for {string} should be {string}") do |task, message|
  instance = journey_instance(@capital_distribution)
  expect(instance.step_result(journey_position(instance, task))&.dig("message")).to eq(message)
end

# Through the real controllers, as the distribution page does
When("I approve the distribution through the app") do
  as_user_request(@user, :post, "/capital_distributions/#{@capital_distribution.id}/approve", {})
  expect(@capital_distribution.reload.approved).to be(true)
end

When("I mark all the distribution's payments completed through the app") do
  as_user_request(@user, :patch, "/capital_distributions/#{@capital_distribution.id}/payments_completed", {})
end

Given("the distribution's payments are marked completed") do
  @capital_distribution.capital_distribution_payments.update_all(completed: true)
end

Given("the distribution's payments are marked completed and emailed") do
  @capital_distribution.capital_distribution_payments.update_all(completed: true, notification_sent: true)
end

When("the distribution's payment notifications are sent by the job") do
  CapitalDistributionPaymentNotificationJob.perform_now(@capital_distribution.id, @user.id)
end

Given("the commitments of the fund have unit type {string}") do |unit_type|
  CapitalCommitment.where(fund_id: @fund.id).update_all(unit_type:)
end

When("the distribution's units are redeemed by the units job") do
  FundUnitsJob.perform_now(@capital_distribution.id, "CapitalDistribution", nil, @user.id)
end

When("I delete the distribution's redeemed units in bulk") do
  travel 1.second
  ids = FundUnit.where(owner_type: "CapitalDistributionPayment", owner_id: @capital_distribution.capital_distribution_payment_ids).pluck(:id)
  expect(ids).not_to be_empty
  FundUnitsBulkActionJob.perform_now(ids, @user.id, "Delete")
end

# The CFO's approval vote on the current (CFO sign-off) step, as the instance page records it
Given("the CFO signs off on the distribution") do
  @journey_record = @capital_distribution.reload
  WorkflowEvaluator.for(@journey_record, cause: :progress)
  instance = journey_instance(@capital_distribution)
  expect(instance.current_step_position).to eq(journey_position(instance, "CFO sign-off")), instance.step_results.inspect
  WorkflowActorResponse.create!(workflow_instance: instance, actor: @user, step_position: instance.current_step_position,
                                state: "Approved", channel: :ui, responded_at: Time.current)
  resolution = WorkflowStepResolver.call(instance: instance.reload)[:resolution]
  WorkflowAdvancer.call(instance:, resolved_state: resolution[:resolved], actor: @user, channel: :ui)
end

When("I untick Completed on one of the distribution's payments through the app") do
  travel 1.second
  payment = @capital_distribution.capital_distribution_payments.first!
  as_user_request(@user, :patch, "/capital_distribution_payments/#{payment.id}", capital_distribution_payment: { completed: "0" })
  expect(payment.reload.completed).to be(false)
end

When("I delete one of the distribution's payments through the app") do
  travel 1.second
  payment = @capital_distribution.capital_distribution_payments.order(:id).last!
  as_user_request(@user, :delete, "/capital_distribution_payments/#{payment.id}", {})
  expect(CapitalDistributionPayment.exists?(payment.id)).to be(false)
end

When("I unapprove one of the distribution's notices through the app") do
  travel 1.second
  @unapproved_notice = Document.where(owner: @capital_distribution.capital_distribution_payments, owner_tag: "Generated").first!
  as_user_request(@user, :patch, Rails.application.routes.url_helpers.document_path(@unapproved_notice),
                  document: { approved: "0" })
  expect(@unapproved_notice.reload.approved).to be(false)
end

# Exercises CapitalDistributionPaymentDocJob's journey hook with the generator stubbed: like the real
# job, only unapproved notices are replaced (DocGenJob skips payments with an approved notice)
When("the distribution's notices are regenerated by the doc job") do
  travel 1.second
  job = CapitalDistributionPaymentDocJob.new
  dist = @capital_distribution
  world = self # inside the stub, self is the job
  job.define_singleton_method(:generate) do |*_args, **_opts|
    dist.capital_distribution_payments.find_each do |payment|
      notices = Document.where(owner: payment, owner_tag: "Generated")
      next if notices.exists?(approved: true)

      notices.find_each(&:destroy)
      world.send(:create_distribution_notice, payment)
    end
  end
  job.define_singleton_method(:valid_inputs) { true }
  job.perform(@capital_distribution.id, nil, @user.id)
end

Then("the {string} confirmation on the distribution should have been reset") do |task|
  instance = journey_instance(@capital_distribution)
  responses = instance.workflow_actor_responses.for_step(journey_position(instance, task))
  expect(responses.active).not_to exist
  expect(responses.archived).to exist
end

Given("the fund has a distribution email") do
  @fund_email = CustomNotification.create!(entity: @entity, owner: @fund, for_type: "CapitalDistribution", subject: "Distribution",
                                           body: "Your distribution", email_method: "send_notification")
end

When("I edit the fund's distribution email") do
  travel 1.second
  as_user_request(@user, :patch, Rails.application.routes.url_helpers.custom_notification_path(@fund_email),
                  custom_notification: { subject: "Distribution — revised" })
end

Given("I remember this distribution as {string}") do |label|
  @remembered_distributions ||= {}
  @remembered_distributions[label] = @capital_distribution
end

Then("on distribution {string} the journey current task should be {string}") do |label, task|
  instance = journey_instance(@remembered_distributions.fetch(label))
  expect(instance.current_step_position).to eq(journey_position(instance, task)), instance.step_results.inspect
end

Then("on distribution {string} the journey message for {string} should be {string}") do |label, task, message|
  instance = journey_instance(@remembered_distributions.fetch(label))
  expect(instance.step_result(journey_position(instance, task))&.dig("message")).to eq(message)
end

Then("on distribution {string} the {string} confirmation should still be recorded") do |label, task|
  instance = journey_instance(@remembered_distributions.fetch(label))
  expect(instance.workflow_actor_responses.active.for_step(journey_position(instance, task))).to exist
end

# The date change runs CapitalDistributionDateChangeJob and then the recompute (inline in tests)
When("I change the distribution's date through the app") do
  travel 1.second
  new_date = @capital_distribution.distribution_date + 1.day
  as_user_request(@user, :patch, "/capital_distributions/#{@capital_distribution.id}",
                  capital_distribution: { distribution_date: new_date.iso8601 })
  expect(@capital_distribution.reload.distribution_date).to eq(new_date)
end

When("the distribution notices are approved by date range") do
  DocumentApprovalJob.perform_now(@entity.id, Date.yesterday, I18n.l(Time.zone.today),
                                  { user_id: @user.id, owner_type: "CapitalDistributionPayment" })
end

When("I delete the distribution through the app") do
  @deleted_distribution_id = @capital_distribution.id
  @deleted_instance_ids = WorkflowInstance.where(workflowable: @capital_distribution).pluck(:id)
  expect(@deleted_instance_ids).not_to be_empty
  as_user_request(@user, :delete, "/capital_distributions/#{@capital_distribution.id}", {})
end

Then("the distribution and its journey should be gone") do
  expect(CapitalDistribution.exists?(@deleted_distribution_id)).to be false
  expect(WorkflowInstance.where(id: @deleted_instance_ids)).not_to exist
end

# ── Real time (E16, E17) ──────────────────────────────────────────────────────

def mark_page_for_reload_check
  @page_marker = SecureRandom.hex(4)
  # A marker on the current DOM proves later assertions ran without a page reload
  page.execute_script("document.body.dataset.journeyMarker = '#{@page_marker}'")
end

When("the distribution's notices are generated by the doc job while the page is open") do
  mark_page_for_reload_check
  job = CapitalDistributionPaymentDocJob.new
  dist = @capital_distribution
  world = self # inside the stub, self is the job
  job.define_singleton_method(:generate) do |*_args, **_opts|
    dist.capital_distribution_payments.find_each { |payment| world.send(:create_distribution_notice, payment) }
  end
  job.define_singleton_method(:valid_inputs) { true }
  job.perform(@capital_distribution.id, nil, @user.id)
end

Given("the distribution is approved and reviewed with notices approved") do
  step %(the distribution's notices are generated and 3 of them is approved)
  step %(both distribution review tasks are marked reviewed)
  @capital_distribution.update!(approved: true, approved_by_user: @user)
end

# Through the real controller, as another session would, while this page stays open
When("a colleague marks the distribution's payments completed while the page is open") do
  mark_page_for_reload_check
  as_user_request(@user, :patch, "/capital_distributions/#{@capital_distribution.id}/payments_completed", {})
end

# ── CFO sign-off (E24, E25) ───────────────────────────────────────────────────

# An older Full template: the CFO sign-off removed and the positions closed up again
Given("the Full distribution journey has no {string} step") do |name|
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: CapitalDistributionJourneySetup::FULL_KEY)
  template.workflow_steps.where(name:).destroy_all
  template.workflow_steps.reorder(:position).each_with_index { |s, idx| s.update_column(:position, idx + 1) }
end

Then("the Full distribution journey should have a {string} step with no approver before {string}") do |name, before|
  steps = WorkflowTemplate.find_by!(entity: @entity, system_key: CapitalDistributionJourneySetup::FULL_KEY).workflow_steps
  step = steps.find_by!(name:)
  expect(step.kind).to eq("human")
  expect(step.workflow_step_actors).to be_empty
  expect(steps.find_by!(name: before).position).to eq(step.position + 1)
  expect(steps.where(name:).count).to eq(1)
end
