# Steps for features/core/task_list_filters.feature — the tasks list's filter
# bar. The bar itself (tasks/_filter_bar) is shared with the kanban board, so
# the "I select ... from the task ... filter" step lives in
# task_board_steps.rb and drives either view.
#
# Task fixtures come from "there are following board tasks for the entity"
# (task_board_steps.rb) and "there are following tasks for the entity"
# (task_category_filtering_steps.rb) — both create plain Tasks, nothing
# board-specific.

When('I go to the tasks page for the investor') do
  visit tasks_path(owner_id: @investor.id, owner_type: 'Investor')
end

# Asserted through the dropdown rather than the model: a category present in the
# data but missing from the select is exactly the bug this covers.
Then('the tasks list should offer the category {string}') do |category|
  expect(page).to have_select('category_filter', with_options: [category])
end

# TaskList ignores investor_id once owner_id is set, so on a record's own tab the
# select would be a control that silently does nothing.
Then('the tasks list should not offer a stakeholder filter') do
  # A typeahead now, not a select — assert on the input it renders.
  expect(page).to have_no_field('stakeholder_filter')
end

Then('the tasks list should offer a contact filter') do
  expect(page).to have_select('touch_point_id')
end

# The embedded tabs load the tasks list into a turbo frame the host page names
# (here "task_list", lazily, once the tab is shown).
When("I open the investor's Tasks tab") do
  visit investor_path(@investor)
  within('#investor_tabs') { click_on('Tasks') }
  expect(page).to have_css('turbo-frame#task_list table#tasks', wait: 10)
end

# A marker on the window object: it survives a turbo frame swap and is wiped by
# a full page load, which is exactly the distinction under test.
When('I remember the current page load') do
  page.execute_script("window.__pageLoadToken = 'kept'")
end

Then('the page should not have reloaded') do
  expect(page.evaluate_script('window.__pageLoadToken')).to eq('kept')
end

# The standalone version of this step (task_board_steps.rb) waits on the URL
# picking up the chosen filter. A frame submit deliberately leaves the address
# bar on the host record's page, so here we wait on the frame re-rendering.
When('I select {string} from the task {string} filter in the tab') do |option, select_id|
  within('turbo-frame#task_list') { select option, from: select_id }
  sleep 1 # requestSubmit -> frame fetch -> re-render
end

# Persist a row that no longer passes its own validations, written past
# validation so it lands in the database invalid. Tags length stands in for the
# real production case (an invalid Document under WithFolder's
# validates_associated), which needs an attachment to reproduce and exercises
# the identical controller path.
Given('the task {string} no longer passes validation') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  expect(task).to be_present
  Task.where(id: task.id).update_all(tags: "x" * 60)
end

# Scoped to #user_alert on purpose: that is the container every layout renders
# unconditionally, and the one the error has to land in. WithTurboFlash's own
# target (#page_alerts) is absent on a page that loaded without a flash.
Then('I should see {string} in the alert area') do |message|
  within('#user_alert') { expect(page).to have_content(message) }
end

Then('the task {string} should not be completed') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  expect(task.reload.completed).to be_falsey
end
