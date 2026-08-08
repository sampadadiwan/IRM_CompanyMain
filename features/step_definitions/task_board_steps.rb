# Steps for features/core/task_board.feature — the tasks kanban board.
#
# Relies on shared steps for login ("Im logged in..."), investor setup
# ("there is an existing investor") and contacts ("there is a contact ... for
# the investor", lp_crm_steps.rb).

# Creates tasks in specific board states. "done" is set via the legacy
# `completed` flag on purpose — it proves Task#sync_status_and_completed derives
# the board status, mirroring what the migration backfill does for old rows.
Given('there are following board tasks for the entity:') do |table|
  table.hashes.each do |row|
    task = Task.new(entity: @user.entity, user: @user, details: row['details'])
    if row['status'] == 'done'
      task.completed = true
    elsif row['status'].present?
      task.status = row['status']
    end
    # "stakeholder: yes" owns the task by @investor — required for a touch point
    # (contact) to be valid; other tasks stay entity-owned like the list steps do
    task.owner = row['stakeholder'].present? ? @investor : @user.entity
    task.touch_point = InvestorAccess.find_by!(email: row['contact']) if row['contact'].present?
    task.assigned_to = User.find_by!(email: row['assigned_to']) if row['assigned_to'].present?
    task.tags = row['tags'] if row['tags'].present?
    # Keep ActionMailer::Base.deliveries clean so the no-email drag assertion
    # isn't polluted by creation notifications (inline ActiveJob adapter)
    task.send_notification_flag = false
    task.save!
  end
end

When('I go to the tasks board page') do
  visit tasks_path(board: true)
end

When('I go to the tasks page showing all tasks') do
  visit tasks_path(completed: :all)
end

# Column titles render as status.titleize ("Todo", "In Progress", "Done");
# parameterize maps them back to the data-status attribute on the drop zone.
Then('I should see {string} in the {string} board column') do |text, column_title|
  within(".task-board-column-body[data-status='#{column_title.parameterize(separator: '_')}']") do
    expect(page).to have_content(text)
  end
end

Then('I should not see {string} in the {string} board column') do |text, column_title|
  within(".task-board-column-body[data-status='#{column_title.parameterize(separator: '_')}']") do
    expect(page).not_to have_content(text)
  end
end

Then('I should see the tasks list') do
  expect(page).to have_css('table#tasks')
end

# The board filters are plain auto-submit selects named by their param
When('I select {string} from the board {string} filter') do |option, select_id|
  select option, from: select_id
  # requestSubmit triggers a full GET reload; wait for it to land (the chosen
  # filter comes back as a query param — URL-encoded, so bracketed ransack
  # params like q[tags_cont] arrive as q%5Btags_cont%5D)
  expect(page).to have_current_path(/#{Regexp.escape(CGI.escape(select_id))}=[^&]/, wait: 10)
  sleep 1 # let the board finish rendering
end

# Capybara's drag_to does not reliably fire HTML5 drag events, so dispatch the
# real dragstart/dragover/drop sequence (with a shared DataTransfer) against the
# actual card and column nodes — this exercises task_board_controller.js and the
# update_status endpoint end to end.
When('I drag the {string} board card to the {string} column') do |details, column_title|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  expect(task).to be_present
  @deliveries_before_drag = ActionMailer::Base.deliveries.size
  page.execute_script(<<~JS, "task_#{task.id}", column_title.parameterize(separator: '_'))
    const [cardId, status] = arguments;
    const card = document.getElementById(cardId);
    const column = document.querySelector(`.task-board-column-body[data-status='${status}']`);
    const dataTransfer = new DataTransfer();
    card.dispatchEvent(new DragEvent('dragstart', { bubbles: true, cancelable: true, dataTransfer }));
    column.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer }));
    column.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer }));
  JS
  sleep 1 # allow the PATCH + turbo_stream replace to land
end

Then('the task {string} should be completed') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  expect(task.completed).to be_truthy
  expect(task.status).to eq('done')
  expect(task.completed_on).to eq(Time.zone.today)
end

Then('no new task emails should have been sent') do
  # A board drag must not notify (send_notification_flag=false in update_status)
  expect(ActionMailer::Base.deliveries.size).to eq(@deliveries_before_drag)
end

When('I toggle the completed checkbox for the task {string}') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  expect(task).to be_present
  within("tr#task_#{task.id}") do
    find('.task-done-checkbox').click
  end
  sleep 1 # turbo_stream row replace after requestSubmit
end
