Given(/^a task recurrence rule exists for entity with:$/) do |table|
  data = table.rows_hash
  start_date = data['start_date'] ? Time.zone.parse(data['start_date']) : nil
  end_date = data['end_date'].present? ? Time.zone.parse(data['end_date']) : nil

  @rule = TaskRecurrenceRule.create!(
    entity: @entity,
    start_date: start_date,
    end_date: end_date,
    rrule: data['details'], # In the feature file we used details for rrule for simplicity
    task_template_payload: {
      details: data['details'],
      category: data['category'],
      entity_id: @entity.id
    }
  )
end

When(/^the recurring task generator job runs$/) do
  # Use travel_to as it is standard in Rails for stubbing Time.current
  target_time = Time.zone.parse("2026-02-05 12:00:00")
  travel_to(target_time)
  RecurringTaskGeneratorJob.perform_now
end

After do
  # Ensure we always travel back even if it fails
  travel_back
end

Then(/^there should be (\d+) tasks created for the recurrence rule$/) do |count|
  expect(Task.where(task_recurrence_rule: @rule).count).to eq(count.to_i)
end

Then(/^each task should have the correct original_start_date$/) do
  tasks = Task.where(task_recurrence_rule: @rule).order(:original_start_date)
  # Basic check: first one should be start_date
  expect(tasks.first.original_start_date.to_date).to eq(@rule.start_date.to_date)

  # Weekly check
  if @rule.rrule.include?('WEEKLY')
    tasks.each_cons(2) do |a, b|
      expect(b.original_start_date - a.original_start_date).to eq(7.days)
    end
  end
end

Then(/^the task recurrence rule should have generated_until set to the end of the quarter$/) do
  @rule.reload
  # Use change_time to ignore sub-second differences
  # Time.current is frozen at 2026-02-05 in the When step, but we are outside that block here.
  # However, the job ran with frozen time 2026-02-05.
  # (2026-02-05 + 3.months) -> 2026-05-05. end_of_quarter -> 2026-06-30.
  expected_horizon = (Time.zone.parse("2026-02-05") + 3.months).end_of_quarter
  expect(@rule.generated_until.to_i).to eq(expected_horizon.to_i)
end

Given(/^a task already exists for the recurrence rule on "([^"]*)"$/) do |date|
  Task.create!(
    @rule.task_template_payload.merge(
      task_recurrence_rule: @rule,
      original_start_date: Time.zone.parse(date),
      due_date: Time.zone.parse(date).to_date,
      entity_id: @rule.entity_id
    )
  )
end

Then(/^there should be only (\d+) tasks in total for the recurrence rule$/) do |count|
  expect(Task.where(task_recurrence_rule: @rule).count).to eq(count.to_i)
end

Then(/^no task should be duplicated for "([^"]*)"$/) do |date|
  expect(Task.where(task_recurrence_rule: @rule, original_start_date: Time.zone.parse(date)).count).to eq(1)
end

Then(/^there should be exactly (\d+) tasks created for the recurrence rule$/) do |count|
  expect(Task.where(task_recurrence_rule: @rule).count).to eq(count.to_i)
end

When('I fill in task {string} with {string}') do |field, value|
  if field == "task_details"
    find("trix-editor[input='task_details_trix_input_task']").set(value)
  else
    fill_in(field, with: value)
  end
end

Then('the last task should be recurring') do
  expect(Task.last.task_recurrence_rule_id).to be_present
end

Then('the last task should not be recurring') do
  expect(Task.last.task_recurrence_rule_id).to be_nil
end

Then('{string} should be visible') do |id|
  expect(page).to have_selector("##{id}", visible: true)
end

Then('{string} should not be checked') do |id|
  expect(find("##{id}")).not_to be_checked
end

When('I check {string}') do |field|
  check(field)
end

When('I uncheck {string}') do |field|
  uncheck(field)
end

When('I select {string} from {string}') do |value, field|
  select(value, from: field)
end

When('I click {string} for the task {string}') do |action, task_details|
  task = Task.all.find { |t| t.details.body.to_plain_text.include?(task_details) }
  within("tr#task_#{task.id}") do
    click_on(action)
  end
  sleep(1)
end

Then('the task {string} should be recurring') do |task_details|
  task = Task.all.find { |t| t.details.body.to_plain_text.include?(task_details) }
  expect(task.reload.task_recurrence_rule_id).to be_present
end

Then('the task {string} should not be recurring') do |task_details|
  task = Task.all.find { |t| t.details.body.to_plain_text.include?(task_details) }
  expect(task.reload.task_recurrence_rule_id).to be_nil
end
