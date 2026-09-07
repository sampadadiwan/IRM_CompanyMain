# Step definitions for features/fund/allocation_run_templates.feature.
#
# The allocation engine is never run here: AllocationGroupRunJob#run_engine is stubbed so
# the scenarios test ordering, fail-early, Pending-as-failure, resume and restart behaviour
# in seconds. Cucumber uses the :inline ActiveJob adapter, so AllocationGroupRunStart runs
# the job (and delivers the completion email) before the next step.

# features/support/env.rb excludes `allocation_runs` from DatabaseCleaner's truncation (for
# suite-wide speed), so rows there are never cleared between scenarios — and MySQL's TRUNCATE
# resets auto-increment on every OTHER table it does clean, including `funds`, so a later
# scenario's freshly created "Feeder Fund" can be assigned the exact fund_id an earlier
# scenario used. A `locked` AllocationRun this feature created for that period then still
# matches on the new fund with the same id. This feature is the first to create `locked`
# runs with specific dates that actually collide this way, so clean up its own rows here
# rather than touching the shared exclusion list, which the whole suite relies on for speed.
After('@allocation_run_templates') do
  fund_ids = [@fund&.id, @fund_b&.id].compact
  next if fund_ids.empty?

  runs = AllocationRun.where(fund_id: fund_ids)
  # delete_all skips the dependent: :nullify callback declared on the association; do it
  # explicitly so a dangling allocation_run_id can never survive, regardless of whether this
  # hook happens to run before or after the built-in DatabaseCleaner truncation of the (not
  # excluded) allocation_group_run_items table.
  AllocationGroupRunItem.where(allocation_run_id: runs.select(:id)).update_all(allocation_run_id: nil)
  runs.delete_all
end

### Helpers ####################################################################

# "key=value;key=value" -> hash with booleans and blanks coerced.
def art_attrs(args)
  args.split(";").each_with_object({}) do |pair, h|
    k, v = pair.split("=", 2)
    v = v.to_s.strip
    h[k.strip.to_sym] = case v
                        when "true" then true
                        when "false" then false
                        when "" then nil
                        else v
                        end
  end
end

def art_fund(which)
  which.to_s.start_with?("second") ? @fund_b : @fund
end

def art_template!(name)
  AllocationRunTemplate.find_by!(entity: @entity, name:)
end

def art_group!(name)
  AllocationRunTemplateGroup.find_by!(entity: @entity, name:)
end

def art_date(str)
  Date.parse(str)
end

# A past allocation run on a fund. Blocker rules are skipped exactly as the controller does
# after its own pre-check, so fixtures do not depend on which rules the entity opted into.
def art_create_allocation_run(fund, attrs = {})
  WithValidationRules.skip do
    AllocationRun.create!({ entity_id: fund.entity_id, fund:, user: @user, run_allocations: true,
                            start_date: Date.new(2024, 1, 1), end_date: Date.new(2024, 3, 31), status: "Success" }.merge(attrs))
  end
end

# A fake engine result: only failure? and [:error] are read by the job.
def art_engine_result(failure, error = nil)
  double("EngineResult", failure?: failure, :[] => error)
end

# Stubs AllocationGroupRunJob#run_engine. `outcomes` maps template name -> :success | :pending
# | "error message"; anything not listed succeeds. Every call is appended to @engine_calls.
# Installs the run_engine stub at most once per scenario, then just swaps out what it should
# do next. RSpec's allow_any_instance_of stub is only reliable the *first* time it's set up
# for a given method within one example — re-calling `allow_any_instance_of(...).to
# receive(...)` after it has already been invoked on a real instance (as happens the second
# time a scenario calls "Given the allocation engine will...") is a documented RSpec::Mocks
# limitation and silently stops applying to later instances. So the stub itself is installed
# once, and its block reads @engine_outcomes fresh on every call — later calls to this method
# just replace that hash (not merge: "will succeed for every template" must clear any earlier
# per-template failure, not layer on top of it), which the already-installed stub picks up
# immediately since it closes over self, not a snapshot of the hash.
def art_stub_engine(outcomes = {})
  @engine_calls ||= []
  @engine_outcomes = outcomes
  return if @engine_stubbed

  @engine_stubbed = true
  calls = @engine_calls
  allow_any_instance_of(AllocationGroupRunJob).to receive(:run_engine) do |_job, template, _group_run, allocation_run|
    calls << template.name
    outcome = @engine_outcomes.fetch(template.name, :success)
    case outcome
    when :success
      # The engine writes Success only when formulas ran; a statements-only run leaves it blank.
      allocation_run.update_column(:status, template.run_allocations? ? "Success" : nil)
      art_engine_result(false)
    when :pending
      allocation_run.update_column(:status, "Pending")
      art_engine_result(false)
    else
      allocation_run.update_column(:status, outcome)
      art_engine_result(true, outcome)
    end
  end
end

def art_start_group(name, from, to, resume: true, user: @user)
  # Clear the array in place rather than reassigning — art_stub_engine's mock closure already
  # captured a reference to the array object created when the engine was stubbed; replacing
  # @engine_calls with a new array here would leave that closure appending to the old one
  # while every assertion reads the new, permanently empty one.
  @engine_calls&.clear
  ActionMailer::Base.deliveries.clear
  @start_result = AllocationGroupRunStart.call(group: art_group!(name), user:, start_date: art_date(from), end_date: art_date(to), resume:)
  @previous_group_run = @group_run
  @group_run = @start_result[:group_run]&.reload
end

### Templates ##################################################################

Given('there is a past allocation run {string} on the first fund') do |args|
  attrs = art_attrs(args)
  attrs[:start_date] = art_date(attrs[:start_date]) if attrs[:start_date]
  attrs[:end_date] = art_date(attrs[:end_date]) if attrs[:end_date]
  @allocation_run = art_create_allocation_run(@fund, attrs)
end

When('I save that allocation run as an allocation run template named {string}') do |name|
  @template = AllocationRunTemplate.from_allocation_run(@allocation_run)
  @template.entity = @entity
  @template.user = @user
  @template.name = name
  @template.save!
end

Then('an allocation run template {string} should exist for the first fund') do |name|
  tmpl = AllocationRunTemplate.find_by(entity: @entity, name:)
  expect(tmpl).not_to be_nil, "Expected allocation run template '#{name}' to exist"
  expect(tmpl.fund_id).to eq(@fund.id)
end

Then('the template {string} should carry {string}') do |name, args|
  tmpl = art_template!(name)
  art_attrs(args).each do |key, value|
    expect(tmpl.public_send(key).to_s).to eq(value.to_s), "Expected #{key} to be #{value.inspect}, got #{tmpl.public_send(key).inspect}"
  end
end

When('I try to create an allocation run template {string} on the first fund') do |args|
  @template = AllocationRunTemplate.new(art_attrs(args).merge(entity: @entity, user: @user, fund: @fund))
  @template.save
end

When('I try to create an allocation run template {string} on the second fund') do |args|
  @template = AllocationRunTemplate.new(art_attrs(args).merge(entity: @entity, user: @user, fund: @fund_b))
  @template.save
end

Then('the template should not be saved with an error containing {string}') do |text|
  expect(@template).not_to be_persisted
  expect(@template.errors.full_messages.join(" ")).to include(text)
end

Given('there is an allocation run template {string} on the first fund') do |args|
  @template = AllocationRunTemplate.create!(art_attrs(args).merge(entity: @entity, user: @user, fund: @fund))
end

Given('there is an allocation run template {string} on the second fund') do |args|
  @template = AllocationRunTemplate.create!(art_attrs(args).merge(entity: @entity, user: @user, fund: @fund_b))
end

# A template that generates statements needs a statement document on the fund.
Given('there is an allocation run template {string} on the first fund with a statement document') do |args|
  @statement_document = FactoryBot.create(:document, entity: @entity, owner: @fund, name: "Investor Statement",
                                                     owner_tag: "SOA Template", template: true, user: @user, folder: @fund.document_folder)
  @template = AllocationRunTemplate.create!(art_attrs(args).merge(entity: @entity, user: @user, fund: @fund,
                                                                  statement_document: @statement_document))
end

Given('the statement document of the template {string} is deleted') do |name|
  art_template!(name).statement_document.destroy!
end

Given('the entity formula tag list is {string}') do |tags|
  @entity.entity_setting.update!(formula_tag_list: tags)
end

When('I try to delete the allocation run template {string}') do |name|
  @template = art_template!(name)
  @template.destroy
end

Then('the template {string} should still exist') do |name|
  expect(AllocationRunTemplate.exists?(entity: @entity, name:)).to be true
end

When('I remove every template from the group {string} by deleting the group') do |name|
  art_group!(name).destroy!
end

Then('I can delete the allocation run template {string}') do |name|
  expect(art_template!(name).destroy).to be_truthy
  expect(AllocationRunTemplate.exists?(entity: @entity, name:)).to be false
end

### Groups #####################################################################

Given('there is an allocation run group {string} with templates {string}') do |name, template_names|
  @group = AllocationRunTemplateGroup.new(entity: @entity, user: @user, name:)
  template_names.split(",").map(&:strip).each_with_index do |tname, idx|
    @group.items.build(allocation_run_template: art_template!(tname), position: idx + 1)
  end
  @group.save!
end

When('I try to create an allocation run group {string} with no templates') do |name|
  @group = AllocationRunTemplateGroup.new(entity: @entity, user: @user, name:)
  @group.save
end

Then('the group should not be saved with an error containing {string}') do |text|
  expect(@group).not_to be_persisted
  expect(@group.errors.full_messages.join(" ")).to include(text)
end

Then('the group {string} should run {string} before {string}') do |group_name, first, second|
  names = art_group!(group_name).ordered_items.map { |i| i.allocation_run_template.name }
  expect(names.index(first)).to be < names.index(second)
end

Given('the group {string} has a finished run for {string} to {string}') do |name, from, to|
  group = art_group!(name)
  @group_run = AllocationGroupRun.create!(entity: @entity, user: @user, allocation_run_template_group: group, group_name: group.name,
                                          start_date: art_date(from), end_date: art_date(to), status: "success",
                                          started_at: 1.hour.ago, finished_at: 30.minutes.ago)
  group.ordered_items.each do |item|
    run = art_create_allocation_run(item.allocation_run_template.fund, start_date: art_date(from), end_date: art_date(to))
    @group_run.items.create!(allocation_run_template: item.allocation_run_template, fund: item.allocation_run_template.fund,
                             template_name: item.allocation_run_template.name, position: item.position, status: "success", allocation_run: run)
  end
end

Given('the group {string} has a running run for {string} to {string}') do |name, from, to|
  group = art_group!(name)
  @group_run = AllocationGroupRun.create!(entity: @entity, user: @user, allocation_run_template_group: group, group_name: group.name,
                                          start_date: art_date(from), end_date: art_date(to), status: "running", started_at: 5.minutes.ago)
  group.ordered_items.each do |item|
    @group_run.items.create!(allocation_run_template: item.allocation_run_template, fund: item.allocation_run_template.fund,
                             template_name: item.allocation_run_template.name, position: item.position, status: "pending")
  end
end

# Simulates a worker that died after the first template finished: that item is success, the rest pending.
Given('the group {string} has a running run for {string} to {string} with {string} already successful') do |name, from, to, done_name|
  step %(the group "#{name}" has a running run for "#{from}" to "#{to}")
  item = @group_run.items.detect { |i| i.template_name == done_name }
  # At this point item.status is still "pending" (set by the step above), so this fund is
  # "busy" by its own not-yet-updated item — the same self-referential case
  # AllocationGroupRunJob works around with skip_fund_busy_check: true when it creates a
  # template's own run.
  run = art_create_allocation_run(item.fund, start_date: art_date(from), end_date: art_date(to), skip_fund_busy_check: true)
  item.update!(status: "success", allocation_run: run, started_at: 4.minutes.ago, finished_at: 3.minutes.ago)
end

When('I delete the group {string}') do |name|
  art_group!(name).destroy!
end

Then('a group run named {string} should still exist without a group') do |name|
  run = AllocationGroupRun.find_by(entity: @entity, group_name: name)
  expect(run).not_to be_nil
  expect(run.allocation_run_template_group_id).to be_nil
  expect(run.items.count).to be_positive
end

### Pre-flight #################################################################

Given('there is a locked allocation run from {string} to {string} on the first fund') do |from, to|
  art_create_allocation_run(@fund, start_date: art_date(from), end_date: art_date(to), locked: true)
end

Given('there is a locked allocation run from {string} to {string} on the second fund') do |from, to|
  art_create_allocation_run(@fund_b, start_date: art_date(from), end_date: art_date(to), locked: true)
end

# An employee (not a company admin) with allocation rights on the first fund only.
Given('there is an employee with allocation rights on the first fund only') do
  @employee = FactoryBot.create(:user, entity: @entity, first_name: "Emp", last_name: "Loyee", curr_role: "employee")
  @employee.add_role(:employee)
  AccessRight.create!(entity: @entity, owner: @fund, user: @employee, metadata: "Employee",
                      permissions: %w[create read update destroy])
end

When('I run the pre-flight check for {string} from {string} to {string}') do |name, from, to|
  @preflight = AllocationGroupRunPreflight.call(group: art_group!(name), user: @user, start_date: art_date(from), end_date: art_date(to), resume: true)
end

When('that employee runs the pre-flight check for {string} from {string} to {string}') do |name, from, to|
  @preflight = AllocationGroupRunPreflight.call(group: art_group!(name), user: @employee, start_date: art_date(from), end_date: art_date(to), resume: true)
end

Then('the pre-flight should be startable') do
  expect(@preflight[:group_blockers]).to be_empty
  expect(@preflight[:startable]).to be(true), "Expected startable; checks: #{@preflight[:checks].map { |c| [c.template.name, c.status, c.messages.map(&:text)] }}"
end

Then('the pre-flight should not be startable') do
  expect(@preflight[:startable]).to be false
end

Then('the pre-flight should not be startable with a group blocker containing {string}') do |text|
  expect(@preflight[:startable]).to be false
  expect(@preflight[:group_blockers].join(" ")).to include(text)
end

def art_check!(name)
  check = @preflight[:checks].detect { |c| c.template.name == name }
  expect(check).not_to be_nil, "No pre-flight check for '#{name}'"
  check
end

Then('the pre-flight check for {string} should be {string}') do |name, status|
  check = art_check!(name)
  expect(check.status.to_s).to eq(status), "Expected #{name} to be #{status}, got #{check.status}: #{check.messages.map(&:text)}"
end

Then('the pre-flight check for {string} should be {string} with a message containing {string}') do |name, status, text|
  check = art_check!(name)
  expect(check.status.to_s).to eq(status), "Expected #{name} to be #{status}, got #{check.status}: #{check.messages.map(&:text)}"
  expect(check.messages.map(&:text).join(" ")).to include(text)
end

When('I try to start the group {string} from {string} to {string}') do |name, from, to|
  art_start_group(name, from, to)
end

Then('no group run should have been recorded') do
  expect(@start_result.success?).to be false
  expect(AllocationGroupRun.where(entity: @entity).count).to eq(0)
end

Then('the first fund should be busy for a manual allocation') do
  expect(AllocationGroupRun.fund_busy?(@fund.id)).to be true
end

Then('the second fund should not be busy for a manual allocation') do
  expect(AllocationGroupRun.fund_busy?(@fund_b.id)).to be false
end

### Running ####################################################################

Given('the allocation engine will succeed for every template') do
  art_stub_engine
end

Given('the allocation engine will fail for {string} with {string}') do |name, message|
  art_stub_engine(name => message)
end

Given('the allocation engine will leave {string} at status {string}') do |name, status|
  art_stub_engine(name => status.downcase.to_sym)
end

When('I start the group {string} from {string} to {string}') do |name, from, to|
  art_start_group(name, from, to)
  expect(@start_result.success?).to be(true), "Group did not start: #{@start_result[:error]} #{@start_result[:group_blockers]} #{@start_result[:checks]&.map { |c| [c.template.name, c.status, c.messages.map(&:text)] }}"
end

When('I start the group {string} from {string} to {string} without resume') do |name, from, to|
  art_start_group(name, from, to, resume: false)
  expect(@start_result.success?).to be(true), "Group did not start: #{@start_result[:error]} #{@start_result[:group_blockers]}"
end

When('the group run job is performed again for that run') do
  # Same array-identity requirement as art_start_group: clear in place, don't reassign — the
  # engine stub installed by "the allocation engine will..." already captured a reference to
  # this exact array.
  @engine_calls&.clear
  AllocationGroupRunJob.new.perform(@group_run.id)
  @group_run.reload
end

Then('the group run should finish with status {string}') do |status|
  expect(@group_run.reload.status).to eq(status), "Group run is #{@group_run.status}: #{@group_run.message}; items: #{@group_run.items.map { |i| [i.template_name, i.status, i.message] }}"
end

Then('the group run items should be {string}') do |expected|
  actual = @group_run.reload.items.ordered.map { |i| "#{i.template_name}=#{i.status}" }.join(",")
  expect(actual).to eq(expected)
end

Then('each group run item should link to a new allocation run for {string} to {string}') do |from, to|
  @group_run.reload.items.each do |item|
    expect(item.allocation_run).not_to be_nil, "#{item.template_name} has no allocation run"
    expect(item.allocation_run.start_date).to eq(art_date(from))
    expect(item.allocation_run.end_date).to eq(art_date(to))
    expect(item.allocation_run.fund_id).to eq(item.fund_id)
    expect(item.allocation_run.allocation_group_run).to eq(@group_run)
  end
end

Then('the engine should have run {string} before {string}') do |first, second|
  expect(@engine_calls).to include(first, second)
  expect(@engine_calls.index(first)).to be < @engine_calls.index(second)
end

Then('the engine should have run only {string} in the latest run') do |name|
  expect(@engine_calls).to eq([name])
end

Then('the group run message should contain {string}') do |text|
  expect(@group_run.reload.message).to include(text)
end

Then('the latest group run should be resumed from the previous one') do
  expect(@group_run.reload.resumed_from).to eq(@previous_group_run)
end

Then('the user should have received an allocation group run email containing {string}') do |text|
  mail = ActionMailer::Base.deliveries.detect { |m| m.subject.to_s.include?("Allocation run group") }
  expect(mail).not_to be_nil, "No allocation group run email; subjects: #{ActionMailer::Base.deliveries.map(&:subject)}"
  expect(mail.to).to include(@user.email)
  expect(mail.subject + mail.body.encoded).to include(text)
end

### UI #########################################################################

When('I visit the allocation run templates page') do
  visit allocation_run_templates_path
  expect(page).to have_content("Allocation Run Templates")
end

Then('I should see the group {string} listing {string} before {string}') do |group_name, first, second|
  card = find(".art-group-card", text: group_name)
  expect(card.text.index(first)).to be < card.text.index(second)
end

When('I open the run modal for the group {string} and check the period {string} to {string}') do |group_name, from, to|
  group = art_group!(group_name)
  find(".art-group-card", text: group_name).click_button("Run")
  within("#runGroupModal-#{group.id}") do
    # The visible field takes the locale format; the locale-date controller fills the hidden ISO input.
    fill_in "start_date_#{group.id}", with: I18n.l(art_date(from))
    fill_in "end_date_#{group.id}", with: I18n.l(art_date(to))
    click_button "Check templates"
  end
end

Then('I should be on the pre-flight page showing {string}') do |text|
  expect(page).to have_content("Pre-flight check", wait: 10)
  expect(page).to have_content(text)
end

When('I confirm the pre-flight with {string}') do |button|
  click_button button
end

Then('I should see the group run progress page with status {string}') do |status|
  expect(page).to have_content("Allocation run group for", wait: 10)
  expect(page).to have_content(status)
  expect(page).to have_css("#progress")
end

When('I visit the allocation screen of the first fund') do
  visit allocate_form_fund_path(@fund, run_allocations: true)
  expect(page).to have_content("Previous Runs")
end

When('I save the first past run as a template named {string}') do |name|
  # Icon-only button; found by aria-label since Bootstrap's Tooltip (data-bs-title) doesn't
  # touch it the way it would a title attribute.
  first(:css, "button[aria-label='Save as template']").click
  within(".modal.show") do
    fill_in "allocation_run_template[name]", with: name
    click_button "Save template"
  end
  expect(page).to have_content("saved", wait: 10)
end
