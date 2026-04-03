Given('I manually start the deal') do
  @deal.update!(start_date: Time.zone.today)
  # activities are already created by CreateDeal service
end

Given('the deal step {string} has the following tasks:') do |step_title, tasks_csv|
  step_has_tasks(step_title, tasks_csv)
end

Given('the deal step {string} has the following tasks: {string}') do |step_title, tasks_csv|
  step_has_tasks(step_title, tasks_csv)
end

def step_has_tasks(step_title, tasks_csv)
  # We need to find the DealActivity template for this deal and title
  activity_template = DealActivity.where(deal_id: @deal.id, deal_investor_id: nil).find_by(title: step_title)

  # If it doesn't exist, we create it to ensure the test can proceed
  activity_template ||= DealActivity.create!(
    deal: @deal,
    entity: @deal.entity,
    title: step_title,
    status: "Template",
    days: 7
  )

  activity_template.update!(tasks_csv: tasks_csv)

  # We also need to ensure that the investor's activities are updated
  # with this new tasks_csv if they already exist
  @deal_investor.create_activities if @deal_investor
end

When('I move the deal investor {string} to the step {string}') do |investor_name, step_title|
  # Use @investor if it matches or it's "the other entity", otherwise find by name
  investor = @investor if @investor && (investor_name == "the other entity")
  investor ||= Investor.find_by(investor_name: investor_name)

  @deal_investor = DealInvestor.find_by(investor: investor, deal: @deal)

  target_activity = @deal_investor.deal_activities.find_by(title: step_title)

  # Set initial activity if not set
  if @deal_investor.deal_activity_id.blank?
    first_activity = @deal_investor.deal_activities.first
    @deal_investor.update!(deal_activity: first_activity)
  end

  # We simulate the PerformActivityAction call
  params = {
    deal_investor_id: @deal_investor.id,
    target_deal_activity_id: target_activity.id,
    initial_deal_activity_id: @deal_investor.deal_activity_id.to_s
  }

  # Pass the current deal_activity as expected by the operation
  result = PerformActivityAction.call(params: params, deal_activity: @deal_investor.deal_activity, current_user_id: @user.id)

  puts "PerformActivityAction failed: #{result[:errors]}" unless result.success?

  expect(result.success?).to be true

  # Ensure background jobs are processed
  @deal_investor.reload
end

Then('the deal investor {string} should have the following tasks:') do |_investor_name, table|
  # We check the Tasks associated with this DealInvestor
  expected_titles = table.hashes.map { |row| row['details'] }

  # Actual tasks - details is rich text
  actual_tasks = Task.where(owner: @deal_investor)
  actual_titles = actual_tasks.map { |t| t.details.to_plain_text.strip }

  expected_titles.each do |title|
    expect(actual_titles).to include(title)
  end
end

And('I should see {string} in the deal tasks view') do |task_title|
  # We visit the Deal Tasks aggregated view
  visit("/tasks/deal_tasks")
  expect(page).to have_content(task_title)
end
