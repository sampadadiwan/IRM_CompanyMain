# Steps for features/core/task_due_date_filtering.feature — the "Due" quick
# filter (Task.due_filter_range / Task::DUE_FILTERS), shared by the list and
# board views. Task fixtures come from "there are following board tasks due
# in each period" (features/step_definitions/task_board_steps.rb) — the step
# itself is board-agnostic, it just creates plain Tasks, so it's reused here.

When('I select {string} from the due date filter dropdown') do |label|
  select label, from: 'due_filter'
  # Wait for the auto-submit reload
  sleep 1
end
