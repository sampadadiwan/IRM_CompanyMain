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
    # "stakeholder: yes" owns the task by @investor directly — required for a
    # touch point (contact) to be valid. "pi"/"commitment" own it by one of the
    # investor's PortfolioInvestment/CapitalCommitment sub-entities instead (see
    # "the investor has a portfolio investment and a capital commitment"),
    # exercising TaskList's investor_id union. Other tasks stay entity-owned
    # like the list steps do.
    task.owner = case row['stakeholder']
                 when 'yes' then @investor
                 when 'pi' then @portfolio_investment
                 when 'commitment' then @capital_commitment
                 else @user.entity
                 end
    task.touch_point = InvestorAccess.find_by!(email: row['contact']) if row['contact'].present?
    task.assigned_to = User.find_by!(email: row['assigned_to']) if row['assigned_to'].present?
    task.tags = row['tags'] if row['tags'].present?
    # Keep ActionMailer::Base.deliveries clean so the no-email drag assertion
    # isn't polluted by creation notifications (inline ActiveJob adapter)
    task.send_notification_flag = false
    task.save!
  end
end

# Fixtures for the stakeholder-filter regression: a PortfolioInvestment ("PI")
# and a CapitalCommitment both belonging to @investor, so a task logged under
# either still counts as "the investor's" task on the board filter.
Given('the investor has a portfolio investment and a capital commitment') do
  fund = FactoryBot.build(:fund, entity: @user.entity, currency: 'USD')
  fund.save!

  investment_instrument = FactoryBot.create(:investment_instrument, entity: @user.entity, portfolio_company: @investor)
  @portfolio_investment = create_valid_portfolio_investment!(
    portfolio_company: @investor,
    investment_instrument: investment_instrument,
    entity: @user.entity,
    fund: fund
  )

  @capital_commitment = FactoryBot.build(:capital_commitment, entity: @user.entity, fund: fund, investor: @investor,
                                                                folio_id: SecureRandom.hex(4),
                                                                unit_type: fund.unit_types.split(',').first&.strip,
                                                                folio_currency: fund.currency)
  @capital_commitment.skip_cf_before_save = true
  @capital_commitment.save!
end

When('I go to the tasks board page') do
  visit tasks_path(board: true)
end

# Due-date filter fixtures: one task per bucket, picked to fall unambiguously
# in only that bucket (see the scenario comment for why -60 rather than -1).
Given('there are following board tasks due in each period') do
  today = Time.zone.today
  {
    'Overdue task' => today - 60,
    'Task due this week' => today,
    'Task due this month' => today,
    'Task due next month' => (today + 1.month).all_month.begin
  }.each do |details, due_date|
    task = Task.new(entity: @user.entity, user: @user, details: details, due_date: due_date, status: 'todo')
    task.send_notification_flag = false
    task.save!
  end
end

# Table dates are day offsets from today (e.g. "-500", "+7", "0"), not absolute
# dates — an absolute completed_on drifts stale as BOARD_DONE_WINDOW (a rolling
# 30-day window) moves forward, eventually aging a fixture out of the Done
# column it was written to test.
def relative_test_date(offset)
  Date.today + offset.to_i.days
end

# Ordering fixtures: due dates (including a deliberately undated task) and
# completion dates, written past the callbacks so completed_on isn't re-stamped
# to today by Task#stamp_completed_on.
Given('there are following dated board tasks:') do |table|
  table.hashes.each do |row|
    task = Task.new(entity: @user.entity, user: @user, details: row['details'])
    task.due_date = relative_test_date(row['due_date']) if row['due_date'].present?
    task.completed = true if row['status'] == 'done'
    task.status = row['status'] if row['status'].present?
    task.send_notification_flag = false
    task.save!
    if row['completed_on'].present?
      Task.where(id: task.id).update_all(completed_on: relative_test_date(row['completed_on']))
    end
  end
end

# Card order within a column — the cards are the column's direct children, so
# their DOM order is the rendered order. Asserts the RELATIVE order of the named
# cards: the column also holds the Background's tasks, and pinning absolute
# positions would just re-encode those fixtures.
Then('the {string} board column should be ordered {string}') do |column_title, expected|
  selector = ".task-board-column-body[data-status='#{column_title.parameterize(separator: '_')}']"
  rendered = all("#{selector} .task-board-card").map { |card| card.text }
  positions = expected.split(',').map(&:strip).map do |details|
    index = rendered.index { |text| text.include?(details) }
    expect(index).not_to be_nil, "#{details.inspect} is not in the #{column_title} column"
    index
  end
  expect(positions).to eq(positions.sort), "cards are out of order: #{expected}"
end

# Deal board fixtures: "deal" rows are deal-level work, "deal_investor" rows
# belong to one investor on that deal — the board must show both.
# @deal/@deal_investor come from "the investor is in an open deal" (lp_crm_steps).
Given('there are following deal board tasks:') do |table|
  table.hashes.each do |row|
    task = Task.new(entity: @user.entity, user: @user, details: row['details'])
    task.status = row['status'] if row['status'].present?
    task.owner = row['owner'] == 'deal' ? @deal : @deal_investor
    task.send_notification_flag = false
    task.save!
  end
end

When('I go to the tasks board page for the deal') do
  visit tasks_path(board: true, deal_id: @deal.id)
end

Then('the board title should name the deal') do
  # A scoped board replaces the generic "Tasks Board" heading with the scope
  # link itself (the owner's bare #to_s, no type prefix), and it links back
  # to the record the board was opened from
  expect(page).to have_link(@deal.name, href: deal_path(@deal))
end

Then('the {string} board card should open its edit form inline') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  within("##{ActionView::RecordIdentifier.dom_id(task)}") do
    link = find('a', text: details)
    # Loads into the board's own frame instead of navigating away, so the board
    # keeps its filters and scroll position
    expect(link['data-turbo-frame']).to eq('new_task')
    # rack_test reports a missing attribute as "" rather than nil
    expect(link[:target].to_s).to be_empty
    expect(link[:href]).to include(edit_task_path(task))
    # board=true makes the save re-render a card rather than a list row
    expect(link[:href]).to include('board=true')
  end
  expect(page).to have_css('turbo-frame#new_task', visible: :all)
end

Then('the {string} board card menu should offer Show, Edit and Delete') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  # visible: :all — a dropdown menu is hidden until its toggle is clicked, and
  # this asserts what the menu contains, not that it is open
  within("##{ActionView::RecordIdentifier.dom_id(task)}", visible: :all) do
    # Show is the only way to the task's own page now that the title edits
    expect(page).to have_link('Show', href: task_path(task), visible: :all)
    expect(page).to have_link('Edit', visible: :all)
    # Delete goes through the shared confirmation modal, so it is a button_to
    # form rather than a link
    expect(page).to have_css("form.deleteButton[action='#{task_path(task)}']", visible: :all)
    expect(page).to have_button('Delete', visible: :all)
  end
end

When('I delete the {string} card from its menu') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  within("##{ActionView::RecordIdentifier.dom_id(task)}") do
    find('a[data-bs-toggle="dropdown"]').click
    click_on('Delete')
  end
  # The shared Bootstrap confirmation modal, not a browser confirm dialog.
  # Found by selector rather than label — the button is translated (t_common(:proceed)).
  find('#confirmModal #confirm_submit button[type="submit"]').click
  sleep 1 # turbo_stream remove
end

When('I open the {string} card\'s edit form') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  within("##{ActionView::RecordIdentifier.dom_id(task)}") { click_on(details) }
  expect(page).to have_css('#task_form', wait: 10)
end

When('I set the task category to {string} and save') do |category|
  select(category, from: 'task_category')
  click_on('Save')
  sleep 1 # turbo_stream card replace
end

Then('I should still be on the tasks board') do
  expect(page).to have_current_path(/board=true/)
  expect(page).to have_css('.task-board')
end

When('I go to the deal tasks tab and click {string}') do |label|
  visit tasks_path(deal_id: @deal.id, embedded_task_context: 'deal_tab')
  # Show All / Incomplete live in the header's Actions menu — see
  # features/support/task_header_helpers.rb
  click_task_header_action(label)
end

When('I edit the task {string} from its own page and save') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  visit edit_task_path(task)
  click_on('Save')
end

Then('the task {string} should still be owned by the deal investor') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  expect(task.reload.owner).to eq(@deal_investor)
end

When('I open the new task form from the deal investor tab') do
  visit new_task_path('task[owner_id]': @deal_investor.id, 'task[owner_type]': 'DealInvestor',
                      embedded_task_context: 'deal_investor_tab')
end

Then('the task owner fields should be hidden but submitted') do
  # Fixed by the tab you opened the form from: shown as a disabled select they
  # only read as editable, so they are submitted hidden instead
  expect(page).not_to have_select('task_owner_type')
  expect(page).not_to have_select('task_owner_id')
  expect(page).to have_field('task_owner_type', type: 'hidden', with: 'DealInvestor', visible: :all)
  expect(page).to have_field('task_owner_id', type: 'hidden', with: @deal_investor.id.to_s, visible: :all)
end

When('I open the new note form from the deal investor tab') do
  visit new_note_path('note[owner_id]': @deal_investor.id, 'note[owner_type]': 'DealInvestor',
                      'note[entity_id]': @entity.id, embedded_note_context: 'deal_investor_tab')
end

Then('the note owner fields should be hidden but submitted') do
  expect(page).not_to have_select('note_owner_type')
  expect(page).not_to have_select('note_owner_id')
  expect(page).to have_field('note_owner_type', type: 'hidden', with: 'DealInvestor', visible: :all)
  expect(page).to have_field('note_owner_id', type: 'hidden', with: @deal_investor.id.to_s, visible: :all)
end

Then('the deal tasks tab should offer a board link for the whole deal') do
  # The tab is embedded, which normally hides the Board link — the deal is the
  # exception, and its link must not pin an owner
  visit tasks_path(deal_id: @deal.id, embedded_task_context: 'deal_tab')
  board_link = find_link('Board')
  expect(board_link[:href]).to include("deal_id=#{@deal.id}")
  # owner_type=Deal would hide every DealInvestor task the deal scope exists to include
  expect(board_link[:href]).not_to include('owner_type')
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

# The stakeholder filter is the one control in the bar that is NOT a select: its
# options would be every investor in the tenant, so it is a typeahead sourced
# from InvestorsController#search. Type enough to trip it (minLength: 2), then
# pick from the jQuery UI menu.
When('I pick {string} in the stakeholder filter') do |name|
  fill_in 'stakeholder_filter', with: name[0, 4]
  find('.ui-autocomplete li', text: name, wait: 10).click
  # The pick sets the hidden investor_id and submits; wait for that to land.
  expect(page).to have_current_path(/investor_id=\d/, wait: 10)
  sleep 1
end

# The filter bar (tasks/_filter_bar) is otherwise plain auto-submit selects named
# by their param, and the list and the board render the same one — hence "task",
# not "board": the same step drives either view.
When('I select {string} from the task {string} filter') do |option, select_id|
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
