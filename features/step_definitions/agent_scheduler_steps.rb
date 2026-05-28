# Step definitions for Agent Scheduler feature tests
# 
#Creates an entity (company/organization) for testing
Given('an entity {string} exists') do |entity_name|
  @entity = FactoryBot.create(:entity, name: entity_name)
end

#Creates a support agent of specified type for the entity
Given('a support agent {string} of type {string} exists') do |agent_name, agent_type|
  @support_agent = FactoryBot.create(:support_agent, name: agent_name, agent_type: agent_type, entity: @entity, enabled: true)
end

# Creates a portfolio company investor for the entity (needed as target for PortfolioCompanyAgent)
Given('a portfolio company {string} exists for the entity') do |name|
  # Create an investor entity (the portfolio company itself)
  investor_entity = FactoryBot.create(:entity, name: name)

  @portfolio_company = FactoryBot.create(:investor,
    investor_entity: investor_entity,
    investor_name: name,
    entity: @entity,
    category: "Portfolio Company",
    primary_email: "contact@#{name.parameterize}.com"
  )
end

# Creates a schedule for the agent using a DataTable
Given('the agent has a schedule with:') do |table|
  # table.rows_hash converts:
  #   | frequency | daily |    =>    { "frequency" => "daily",
  #   | enabled   | true  |           "enabled" => "true" }
  attributes = table.rows_hash

  schedule_attrs = {
    support_agent: @support_agent,
    entity: @entity,
    frequency: attributes['frequency'],
    enabled: attributes['enabled'] == 'true',
    run_at_time: attributes['run_at_time'] || '09:00',
    timezone: attributes['timezone'] || 'UTC'
  }

  # Handle notification settings if provided
  schedule_attrs[:notify_on_failure] = attributes['notify_on_failure'] == 'true' if attributes.key?('notify_on_failure')
  schedule_attrs[:notify_on_success] = attributes['notify_on_success'] == 'true' if attributes.key?('notify_on_success')
  schedule_attrs[:notify_on_partial_success] = attributes['notify_on_partial_success'] == 'true' if attributes.key?('notify_on_partial_success')

  @schedule = FactoryBot.create(:agent_schedule, schedule_attrs)
end

# Sets run_at_time to a few minutes ahead so AgentDailySchedulerService doesn't skip it
Given("the schedule's run_at_time is in the future") do
  @schedule.update!(run_at_time: Time.current.advance(minutes: 5))
end

# Forces next_run_at into the past so SchedulerPollingJob's .due scope picks it up
Given("the schedule's next_run_at is in the past") do
  @schedule.update_column(:next_run_at, 1.hour.ago)
end

# Runs AgentDailySchedulerService directly (same thing DailyMorningJob calls at line 47)
When('the daily morning job runs') do
  @execution_log_count_before = AgentExecutionLog.count
  AgentDailySchedulerService.new.call
end

# Runs SchedulerPollingJob directly — picks up schedules where next_run_at <= now
When('the scheduler polling job runs') do
  @execution_log_count_before = AgentExecutionLog.count
  SchedulerPollingJob.new.perform
end

Then("the schedule's next_run_at should be in the future") do
  expect(@schedule.reload.next_run_at).to be > Time.current
end

Then('no execution log should be created') do
  expect(AgentExecutionLog.count).to eq(@execution_log_count_before)
end


#Verifies that an execution log was created
Then('an execution log should be created') do
  expect(AgentExecutionLog.count).to be > @execution_log_count_before
  @execution_log = AgentExecutionLog.last
end

#Verifies the execution log has expected attributes
Then('the execution log should have:') do |table|
  attributes = table.rows_hash

  attributes.each do |key, expected_value|
    actual_value = @execution_log.send(key).to_s
    expect(actual_value).to eq(expected_value),
      "Expected #{key} to be '#{expected_value}', but got '#{actual_value}'"
  end
end


# --- Retry Setup ---
Given('the schedule has retry settings:') do |table|
  attributes = table.rows_hash
  @schedule.update!(
    retry_count: attributes['retry_count'].to_i,
    retry_interval_minutes: attributes['retry_interval_minutes'].to_i
  )
end


# --- Notification Setup ---
Given('a notification recipient user exists') do
  @notification_user = FactoryBot.create(:user, entity: @entity)
  @schedule.update!(failure_notification_user_ids: [@notification_user.id])
end

Given('the schedule has notification settings:') do |table|
  attributes = table.rows_hash
  update_attrs = {}
  update_attrs[:notify_on_success]         = attributes['notify_on_success'] == 'true'         if attributes.key?('notify_on_success')
  update_attrs[:notify_on_failure]         = attributes['notify_on_failure'] == 'true'         if attributes.key?('notify_on_failure')
  update_attrs[:notify_on_partial_success] = attributes['notify_on_partial_success'] == 'true' if attributes.key?('notify_on_partial_success')
  @schedule.update!(update_attrs)
end

Given('the test agent will raise on step two') do
  # Stub a method that PortfolioCompanyAgent actually has
  allow_any_instance_of(PortfolioCompanyAgent).to receive(:check_kpi_submission) do |_instance, ctx, **|
    raise StandardError, "Simulated error in check_kpi_submission"
  end
end


# --- Execution ---
When('the agent runner job executes') do
  # Stub notifications — prevents actual delivery, allows have_received assertions
  @notifier_double = double('notifier_delivered')
  allow(@notifier_double).to receive(:deliver_later)
  allow(AgentSchedulerNotifier).to receive(:with).and_return(@notifier_double)

  @mailer_double = double('mailer_action')
  allow(@mailer_double).to receive(:deliver_later)
  allow(@mailer_double).to receive(:agent_error_internal).and_return(@mailer_double)
  allow(AgentSchedulerMailer).to receive(:with).and_return(@mailer_double)

  @execution_log = AgentExecutionLog.last
  AgentRunnerJob.new.perform(@execution_log.id)
  @execution_log.reload
end



# --- Execution Assertions ---
Then('the execution log status should be {string}') do |status|
  expect(@execution_log.status).to eq(status)
end

Then('the error message should contain {string}') do |text|
  expect(@execution_log.error_message).to include(text)
end


Then('the last execution log status should be {string}') do |status|
  expect(@execution_log.status).to eq(status)
end


# --- Notification Assertions ---
Then('a failure notification should be sent to the configured users') do
  expect(AgentSchedulerNotifier).to have_received(:with).with(
    hash_including(email_method: :agent_failure)
  )
end

Then('a success notification should be sent to the configured users') do
  expect(AgentSchedulerNotifier).to have_received(:with).with(
    hash_including(email_method: :agent_success)
  )
end



Then('an internal error notification should be sent') do
  expect(AgentSchedulerMailer).to have_received(:with).with(
    hash_including(execution_log_id: @execution_log.id)
  )
end
