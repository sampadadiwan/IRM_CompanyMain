# The tasks list header (tasks/_index.html.erb) keeps Show All, Incomplete and
# Import Tasks inside an "Actions" dropdown — only New Task and the Board/List
# view toggle are standalone buttons. Bootstrap leaves a collapsed menu's links
# in the DOM but hidden, and every scenario here runs under the Playwright driver
# (Capybara.default_driver, features/support/env.rb), so Capybara refuses to click
# them until the menu is open. Untagged scenarios are no exception — this suite
# has no rack_test path where the hidden-element rule wouldn't apply.
#
# Everything happens inside .task_header, and that scoping is load-bearing, not
# tidiness: the stat cards above the list (tasks/_stats) are links whose text
# contains "Completed", "Incomplete", "Delayed" and "Due this week". A page-wide
# lookup matches the card rather than the header control — Capybara's :smart
# matching only prefers the header because its text is an exact match, which
# stops being true once the control is hidden inside the menu. Clicking the card
# instead puts a ransack `completed` condition into q, which then rides along
# through every later filter link and quietly narrows the list.
#
# Clicks straight through when the label is already visible in the header, so the
# same step works for New Task and the Board/List toggle, and would keep working
# if an action were ever promoted back out of the menu. That check also makes the
# call idempotent when the menu happens to be open already: re-clicking "Actions"
# would toggle it shut.
def click_task_header_action(label)
  within('.task_header') do
    click_on('Actions') unless page.has_link?(label, wait: 0)
    click_on(label)
  end
end
