Given('I manually start the deal') do
  @deal.update!(start_date: Time.zone.today)
  # activities are already created by CreateDeal service
end

Given('I am on the deal tasks page for {string}') do |deal_name|
  @deal = Deal.find_by(name: deal_name)
  visit(tasks_path(deal_id: @deal.id, embedded_task_context: "deal_tab"))
  expect(page).to have_selector("#task_list", wait: 20)
end

When('I open the new task form') do
  click_on("New Task", match: :first)
  expect(page).to have_selector("#task_form", wait: 20)
end

Then('the task For field should have deal investor options') do
  expect(page).to have_select("task_owner_id")
  options = page.all("#task_owner_id option").map { |o| o.text.strip }.reject(&:blank?)
  expect(options).not_to be_empty
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

Then('the deal investor {string} should have the following tasks:') do |investor_name, table|
  # Lookup investor if @deal_investor is nil
  unless @deal_investor
    investor = @investor if @investor && (investor_name == "the other entity")
    investor ||= Investor.find_by(investor_name: investor_name)
    @deal_investor = DealInvestor.find_by(investor: investor, deal: @deal)
  end

  # We check the Tasks associated with this DealInvestor
  expected_titles = table.hashes.map { |row| row['details'] }

  # Wait for tasks to be generated (async job)
  max_wait = 10
  start_time = Time.now
  actual_titles = []

  loop do
    actual_tasks = Task.where(owner: @deal_investor)
    actual_titles = actual_tasks.map { |t| t.details.to_plain_text.strip }

    break if expected_titles.all? { |title| actual_titles.include?(title) }
    raise "Investor tasks not found. Expected: #{expected_titles}, Actual: #{actual_titles}" if Time.now - start_time > max_wait

    sleep 1
  end

  expected_titles.each do |title|
    expect(actual_titles).to include(title)
  end
end

And('I should see {string} in the deal tasks view') do |task_title|
  # We visit the Deal Tasks aggregated view
  visit("/tasks/deal_tasks")
  expect(page).to have_content(task_title)
end

Given('I am on the grid view of the deal {string}') do |deal_name|
  @deal = Deal.find_by(name: deal_name)
  visit(deal_path(@deal, grid_view: true))
  # Wait for ag-grid
  expect(page).to have_selector("#deals_list_grid .ag-root-wrapper", wait: 20)
end

When('I mark the activity {string} as completed for investor {string} in the grid') do |step_title, investor_name|
  # Use @investor if it matches or it's "the other entity", otherwise find by name
  investor = @investor if @investor && (investor_name == "the other entity")
  investor ||= Investor.find_by(investor_name: investor_name)
  @deal_investor = DealInvestor.find_by(investor: investor, deal: @deal)

  raise "DealInvestor not found for #{investor_name}" unless @deal_investor

  # Find the activity record
  @deal_activity = @deal_investor.deal_activities.find_by(title: step_title)
  raise "DealActivity #{step_title} not found for investor" unless @deal_activity

  # Ensure the deal_investor's current step is set to the activity being completed.
  # "manually start the deal" sets it to the first step (e.g. "Info Deck Sent"),
  # but the test may intend to complete a later step — update it and reload the page
  # so the ag-grid sees the correct initial state when it sends the PATCH request.
  if @deal_investor.deal_activity_id != @deal_activity.template_id
    @deal_investor.update!(deal_activity_id: @deal_activity.template_id)
    visit(deal_path(@deal, grid_view: true))
  end

  # --- START OF COPIED CODE FROM deal_investor.rb ---

  # 1. Wait for ag-grid to be completely mounted
  expect(page).to have_selector("#deals_list_grid .ag-root-wrapper", wait: 20)

  # Wait for rows to populate
  expect(page).to have_selector("#deals_list_grid .ag-row", wait: 20)

  # 2. Triggering the Inline Editor (UI Simulation)
  # Scroll cell into view using grid API (safer than native scroll for ag-grid)
  page.execute_script(%{
    const gridApi = window.DealsGrid.gridOptions.api;
    const rowId = 'deal_investor_#{@deal_investor.id}';
    const rowNode = gridApi.getRowNode(rowId);
    if (rowNode) {
      gridApi.ensureNodeVisible(rowNode);
      gridApi.ensureColumnVisible('activity_#{@deal_activity.template_id}');
    } else {
      window.rowNodeMissing = true;
    }
  })

  raise "Row node not found in ag-grid for deal_investor_#{@deal_investor.id}" if page.evaluate_script("window.rowNodeMissing")

  # Find the specific cell
  row_selector = ".ag-center-cols-container .ag-row[row-id='deal_investor_#{@deal_investor.id}']"
  col_selector = "[col-id='activity_#{@deal_activity.template_id}']"
  cell = find("#{row_selector} #{col_selector}")

  # Click the activity badge to open the floating menu (new floating-menu UI)
  badge = cell.find(".activity-badge", wait: 5)
  badge.click

  # Wait for the floating menu to appear and click "Complete"
  floating_menu = find("#deals-activity-floating-menu", wait: 5)
  floating_menu.find("[data-status='complete']", wait: 5).click

  # Wait for the floating menu to hide
  expect(page).to have_no_selector("#deals-activity-floating-menu[style*='display: block']", wait: 5)

  # Wait for the UI to reflect the change visually
  within(row_selector) do
    expect(page).to have_content("Complete", wait: 10)
  end

  # --- END OF COPIED CODE ---
end

When('I try to change the activity {string} for investor {string} from the grid') do |step_title, investor_name|
  investor = @investor if @investor && (investor_name == "the other entity")
  investor ||= Investor.find_by(investor_name: investor_name)
  @deal_investor = DealInvestor.find_by(investor: investor, deal: @deal)

  raise "DealInvestor not found for #{investor_name}" unless @deal_investor

  @deal_activity = @deal_investor.deal_activities.find_by(title: step_title)
  raise "DealActivity #{step_title} not found for investor" unless @deal_activity

  if @deal_investor.deal_activity_id != @deal_activity.template_id
    @deal_investor.update!(deal_activity_id: @deal_activity.template_id)
    visit(deal_path(@deal, grid_view: true))
  end

  expect(page).to have_selector("#deals_list_grid .ag-root-wrapper", wait: 20)
  expect(page).to have_selector("#deals_list_grid .ag-row", wait: 20)

  page.execute_script(<<~JS)
    window.__dealActivityPatchCount = 0;
    if (!window.__dealActivityPatchSpyInstalled) {
      var originalFetch = window.fetch;
      window.fetch = function() {
        try {
          var input = arguments[0];
          var init = arguments[1] || {};
          var url = '';

          if (typeof input === 'string') {
            url = input;
          } else if (input && input.url) {
            url = input.url;
          }

          var method = (init.method || 'GET').toUpperCase();
          if (url.indexOf('/deal_activities/') !== -1 && url.indexOf('.json') !== -1 && method === 'PATCH') {
            window.__dealActivityPatchCount = (window.__dealActivityPatchCount || 0) + 1;
          }
        } catch (e) {
        }

        return originalFetch.apply(this, arguments);
      };
      window.__dealActivityPatchSpyInstalled = true;
    }
  JS

  page.execute_script(%{
    const gridApi = window.DealsGrid.gridOptions.api;
    const rowId = 'deal_investor_#{@deal_investor.id}';
    const rowNode = gridApi.getRowNode(rowId);
    if (rowNode) {
      gridApi.ensureNodeVisible(rowNode);
      gridApi.ensureColumnVisible('activity_#{@deal_activity.template_id}');
    } else {
      window.rowNodeMissing = true;
    }
  })

  raise "Row node not found in ag-grid for deal_investor_#{@deal_investor.id}" if page.evaluate_script("window.rowNodeMissing")

  row_selector = ".ag-center-cols-container .ag-row[row-id='deal_investor_#{@deal_investor.id}']"
  col_selector = "[col-id='activity_#{@deal_activity.template_id}']"
  cell = find("#{row_selector} #{col_selector}")

  badge = cell.find(".activity-badge", wait: 5)
  badge.click

  menu = find("#deals-activity-floating-menu", wait: 5)
  expect(menu).to have_no_selector("[data-status='complete']", visible: true)
end

Then('no deal activity patch request should be sent from the grid') do
  patch_count = page.evaluate_script('window.__dealActivityPatchCount || 0')
  expect(patch_count).to eq(0)
end

Then('the current activity for investor {string} should be the next activity after {string}') do |investor_name, step_title|
  # Use @investor if it matches or it's "the other entity", otherwise find by name
  investor = @investor if @investor && (investor_name == "the other entity")
  investor ||= Investor.find_by(investor_name: investor_name)
  @deal_investor = DealInvestor.find_by(investor: investor, deal: @deal)

  # Find the activity that was just completed
  old_activity = @deal_investor.deal_activities.find_by(title: step_title)
  next_activity = @deal_investor.deal_activities.where("sequence > ?", old_activity.sequence).first

  # Reload to check DB update
  max_wait = 10
  start_time = Time.now
  loop do
    @deal_investor.reload
    # We check if the name of the current activity matches the next activity's name
    break if next_activity.nil? || (@deal_investor.deal_activity&.title == next_activity.title)
    raise "Investor current step did not advance to #{next_activity.title} in database within #{max_wait}s. Current: #{@deal_investor.deal_activity&.title}" if Time.now - start_time > max_wait

    sleep 1
  end

  expect(@deal_investor.deal_activity.title).to eq(next_activity.title) if next_activity
end

Given('the current activity for investor {string} is {string}') do |investor_name, step_title|
  investor = @investor if @investor && (investor_name == "the other entity")
  investor ||= Investor.find_by(investor_name: investor_name)
  @deal_investor = DealInvestor.find_by(investor: investor, deal: @deal)

  activity = @deal_investor.deal_activities.find_by(title: step_title)
  @deal_investor.update!(deal_activity_id: activity.template_id)
end

Then('the current activity for investor {string} should still be {string}') do |investor_name, step_title|
  investor = @investor if @investor && (investor_name == "the other entity")
  investor ||= Investor.find_by(investor_name: investor_name)
  @deal_investor = DealInvestor.find_by(investor: investor, deal: @deal)

  @deal_investor.reload
  expect(@deal_investor.deal_activity.title).to eq(step_title)
end
