# Steps for features/core/task_due_date_filtering.feature — the "Due" quick
# filter (Task.due_filter_range / Task::DUE_FILTERS), shared by the list and
# board views. Task fixtures come from "there are following board tasks due
# in each period" (features/step_definitions/task_board_steps.rb) — the step
# itself is board-agnostic, it just creates plain Tasks, so it's reused here.

When('I select {string} from the due date filter dropdown') do |label|
  select label, from: 'due_filter'
  # Was sleep 1: the select submits a GET form that navigates the page (_filter_bar.html.erb), so
  # wait for the URL to carry the chosen value - the next step may click "Board", whose link is
  # built from the current params. Non-raising, like the sleep: the assertions that follow decide
  value = find_field('due_filter').value
  page.has_current_path?(/[?&]due_filter=#{Regexp.escape(value)}(&|$)/)
end
