# Steps for the caret menu that sits next to each investor name in the deal's
# investor grid (features/deal/deal_investor_row_actions.feature).
#
# The menu is built in JS by deals_list_ag_grid_controller#setupRowActionsMenu and
# appended to <body>, not to the row — AG Grid virtualises rows, so a per-row menu
# would be torn out from under the click. That is why the menu is looked up by its
# document-level id rather than inside the grid.

ROW_ACTIONS_MENU = "#deals-row-actions-menu".freeze
SIDEPANEL = "#dealInvestorSidepanel".freeze

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

# Creates one deal investor per comma-separated name, each stamped a minute later
# than the last. None of them is left with a last_interaction_date, so the grid falls
# back to updated_at desc and the LAST name given starts at the top — which is what
# the sort-order scenarios then flip with a dated note or a completed task.
Given('the deal has investors named {string}') do |names|
  @named_deal_investors ||= {}

  # Park anything the Background already created well behind the named ones, so
  # the top of the grid is decided only by the names in this step.
  @deal.deal_investors.update_all(updated_at: 1.hour.ago, created_at: 1.hour.ago,
                                  last_interaction_date: nil)

  names.split(",").map(&:strip).each_with_index do |name, index|
    investor_entity = FactoryBot.create(:entity, entity_type: "Investor", name: name)
    investor = FactoryBot.create(:investor,
                                 entity: @deal.entity,
                                 investor_entity: investor_entity,
                                 investor_name: name)
    deal_investor = FactoryBot.create(:deal_investor,
                                      deal: @deal,
                                      entity: @deal.entity,
                                      investor: investor,
                                      status: "Active")

    # update_columns so the stagger is not undone by the timestamps this write
    # would otherwise set. last_interaction_date is cleared because creating the
    # investor sets its status, which counts as an interaction and would otherwise
    # put every row on today's date with nothing left for a note to outrank.
    stamp = (10 - index).minutes.ago
    deal_investor.update_columns(created_at: stamp, updated_at: stamp, last_interaction_date: nil)

    @named_deal_investors[name] = deal_investor
  end

  @deal.reload
end

Given('the deal investor {string} last interacted {string}') do |name, when_|
  date = case when_
         when "today"     then Time.zone.today
         when "yesterday" then Time.zone.yesterday
         else Date.parse(when_)
         end

  named_deal_investor(name).update_column(:last_interaction_date, date)
end

# ---------------------------------------------------------------------------
# Opening the menu and picking an action
# ---------------------------------------------------------------------------

When('I open the row actions menu for the deal investor') do
  open_row_actions_menu_for(@deal_investor)
end

When('I open the row actions menu for {string}') do |name|
  open_row_actions_menu_for(named_deal_investor(name))
end

When('I choose {string} from the row actions menu') do |label|
  find("#{ROW_ACTIONS_MENU} [data-row-action]", text: label, match: :prefer_exact, wait: 10).click
  # Every action opens the offcanvas; waiting on it here keeps the assertions that
  # follow from racing the panel's frame load.
  expect(page).to have_selector("#{SIDEPANEL}.show", wait: 20)
end

# ---------------------------------------------------------------------------
# View / Edit
# ---------------------------------------------------------------------------

Then('the investor sidepanel should show the deal investor details') do
  within(SIDEPANEL) do
    # The card header (investor name + collapse toggle) is always on screen.
    expect(page).to have_selector(".toggle-card-title", text: @deal_investor.investor_name, wait: 20)
    # The body is a ToggleCard, so whether it starts expanded is a view decision —
    # visible: :all keeps this step about "the details were rendered", not about
    # the card's default state.
    details = find(".show_deal_investor", visible: :all, wait: 10)
    expect(details.text(:all)).to include(@deal_investor.status)
    expect(details.text(:all)).to include(@deal_investor.deal.name)
    # The read-only panel, not the form.
    expect(page).not_to have_selector("#deal_investor_tier", visible: :all)
  end
end

# Expanding is what a user does next, and it is the only way the details become
# readable while the card ships collapsed.
When('I expand the deal investor details card') do
  within(SIDEPANEL) do
    find(".toggle-card-title", text: @deal_investor.investor_name, wait: 10).click
    expect(page).to have_selector(".show_deal_investor.show", wait: 10)
    expect(page).to have_content(@deal_investor.status, wait: 10)
  end
end

Then('the investor sidepanel should show the deal investor edit form') do
  within(SIDEPANEL) do
    expect(page).to have_selector(".edit_deal_investor", wait: 20)
    expect(page).to have_selector("#deal_investor_tier", wait: 10)
    expect(page).to have_selector("#saveButton")
  end
end

When('I set the deal investor tier to {string} in the sidepanel and save') do |tier|
  within(SIDEPANEL) do
    fill_in("deal_investor_tier", with: tier)
    find("#saveButton").click
  end
  sleep(2)
end

Then('the deal investor tier should be {string}') do |tier|
  expect(@deal_investor.reload.tier).to eq(tier)
end

# ---------------------------------------------------------------------------
# Notes
# ---------------------------------------------------------------------------

Then('the note form should open in the sidepanel') do
  within(SIDEPANEL) do
    # The panel opens on the Notes tab, then the controller clicks "New Note" once
    # the lazy notes_frame has loaded — hence the long wait.
    expect(page).to have_selector("#new_note #note_details", wait: 30)
  end
end

When('I fill in the note details with {string} and save') do |details|
  fill_in_and_save_note(details)
end

# The "On" date is what actually moves the investor up the grid — an undated note
# leaves last_interaction_date alone.
When('I fill in the note details with {string} dated today and save') do |details|
  fill_in_and_save_note(details, on: Time.zone.today)
end

When('I fill in the note details with {string} dated {string} and save') do |details, on|
  fill_in_and_save_note(details, on: Date.parse(on))
end

When('I cancel the note form') do
  within(SIDEPANEL) do
    within("#new_note") { click_on("Cancel") }
  end
end

Then('the note form should be closed') do
  within(SIDEPANEL) do
    expect(page).not_to have_selector("#new_note #note_details", wait: 10)
  end
end

Then('the deal investor should have a note {string}') do |details|
  note = Note.where(owner: current_row_action_deal_investor).last
  expect(note).to be_present
  expect(note.details.body.to_plain_text).to include(details)
end

Then('the deal investor should have no notes') do
  expect(Note.where(owner: current_row_action_deal_investor).count).to eq(0)
end

# ---------------------------------------------------------------------------
# Tasks
# ---------------------------------------------------------------------------

Then('the task form should open in the sidepanel') do
  within(SIDEPANEL) do
    expect(page).to have_selector("#new_task #task_form", wait: 30)
  end
end

When('I fill in the task details with {string} and save') do |details|
  within(SIDEPANEL) do
    find("#new_task trix-editor[input='task_details_trix_input_task']", wait: 20).set(details)
    within("#new_task") { click_on("Save") }
  end
  sleep(2)
end

# The task form has no frame-clear "Cancel" like the note form does — its dismiss
# control is the "Close" link, which drops the form card (access_controller#close).
When('I cancel the task form') do
  within(SIDEPANEL) do
    find("#new_task a", text: "Close", wait: 10).click
  end
end

Then('the task form should be closed') do
  within(SIDEPANEL) do
    expect(page).not_to have_selector("#new_task #task_form", wait: 10)
  end
end

Then('the deal investor should have a task {string}') do |details|
  task = Task.where(owner: current_row_action_deal_investor).last
  expect(task).to be_present
  expect(task.details.body.to_plain_text).to include(details)
end

Then('the deal investor should have no tasks') do
  expect(Task.where(owner: current_row_action_deal_investor).count).to eq(0)
end

# The Tasks tab lists each task with a "done" checkbox that posts to
# TasksController#completed — the same route the standalone task list uses.
When('I complete the task for {string} from the sidepanel') do |name|
  deal_investor = named_deal_investor(name)
  open_row_actions_menu_for(deal_investor)
  step 'I choose "View" from the row actions menu'

  within(SIDEPANEL) do
    # The panel's pane ids are scoped with "-di-<deal investor id>" so they don't
    # collide with the deal's own tab strip, which is in the DOM at the same time
    # (see deal_investors/_deal_investor_deal_details.html.erb). The pane is a lazy
    # turbo-frame, so revealing the tab is what loads the task list.
    find("a[href='#tasks-tab-di-#{deal_investor.id}']", wait: 20).click
    find(".task-done-checkbox", wait: 30).click
  end

  # Poll rather than sleep: the checkbox submits over turbo and the assertion that
  # follows reloads the page, which would otherwise race the write.
  Timeout.timeout(20) do
    sleep(0.5) until Task.where(owner: deal_investor).exists?(completed: true)
  end
end

# ---------------------------------------------------------------------------
# Grid ordering
# ---------------------------------------------------------------------------

Then('the deal investor {string} should be the first row in the investor grid') do |name|
  deal_investor = named_deal_investor(name)

  expect(page).to have_selector("#deals_list_grid .ag-center-cols-container .ag-row", wait: 20)
  # Scoped to the center container: pinned columns render a second .ag-row with the
  # same row-id, which would make the match ambiguous.
  expect(page).to have_selector(
    "#deals_list_grid .ag-center-cols-container .ag-row[row-index='0'][row-id='deal_investor_#{deal_investor.id}']",
    wait: 20
  )
end

Then('the deal investor {string} last interaction date should be today') do |name|
  expect(named_deal_investor(name).reload.last_interaction_date).to eq(Time.zone.today)
end

Then('the deal investor {string} should have no last interaction date') do |name|
  expect(named_deal_investor(name).reload.last_interaction_date).to be_nil
end

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Clicks the caret in the given row. The caret is keyed by data-id rather than by
# position so it survives the grid re-sorting between steps.
def open_row_actions_menu_for(deal_investor)
  @row_action_deal_investor = deal_investor

  expect(page).to have_selector("#deals_list_grid .ag-root-wrapper", wait: 20)
  caret = find("#deals_list_grid .deals-row-actions[data-id='#{deal_investor.id}']", wait: 20)
  caret.click

  expect(page).to have_selector(ROW_ACTIONS_MENU, visible: true, wait: 10)
end

def fill_in_and_save_note(details, on: nil)
  within(SIDEPANEL) do
    find("#new_note #note_details", wait: 20).set(details)
    fill_in("note_on", with: on.strftime("%Y-%m-%d")) if on
    within("#new_note") { click_on("Save") }
  end
  sleep(2)
end

def named_deal_investor(name)
  @named_deal_investors&.[](name) ||
    DealInvestor.find_by(deal_id: @deal.id, investor_name: name) ||
    raise("No deal investor named #{name.inspect} in this deal")
end

# The note/task assertions run against whichever row's menu was last opened, so a
# scenario that never opened one still falls back to the background investor.
def current_row_action_deal_investor
  @row_action_deal_investor || @deal_investor
end
