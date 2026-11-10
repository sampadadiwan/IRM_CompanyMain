# The task form's details editor. It goes away once the create response has rendered - the frame's
# stream blanks the form, a standalone form redirects to the task - which is after the save and its
# after_commit notification (inline jobs) have run.
TASK_FORM_EDITOR = "trix-editor[input='task_details_trix_input_task']".freeze

Given('I am at the tasks page') do
  visit("/tasks")
  # No sleep(1): visit waits for the page load and the next steps' finders wait for content
end

# Reproduces a pre-ActionText row: no rich_text record, text in the legacy
# `details` column only. update_all because assigning `details` on a
# has_rich_text model writes the ActionText record, not the column.
Given('a legacy task {string} exists') do |text|
  task = Task.new(entity: @user.entity, user: @user, details: 'placeholder')
  task.send_notification_flag = false
  task.save!
  task.rich_text_details&.destroy
  Task.where(id: task.id).update_all(details: "<div>#{text}</div>")
end

When('I create a new task with details {string} and due date {string}') do |details, due_date|
  click_on("New Task", match: :first)
  find(TASK_FORM_EDITOR).set(details)
  fill_in('task_due_date', with: due_date)
  select(@user.full_name, from: 'task_assigned_to_id')
  click_on("Save")
  # Was sleep(2): the next step reads Task.last, so wait for the create response. Non-raising
  # (has_no_css? returns false if a validation error keeps the form up) - the next step decides
  page.has_no_css?(TASK_FORM_EDITOR)
end

Then('a task should be created with details {string}') do |details|
  Task.last.should_not be_nil
  Task.last.details.body.to_plain_text.should include(details)
end

Given('the following tasks exist:') do |table|
  table.hashes.each do |row|
    # Assuming @user and @entity are set from Background
    Task.create!(
      details: row['details'],
      completed: row['completed'] == 'true',
      entity: @entity,
      user: @user,
      owner: @entity # Setting owner to entity as default
    )
  end
end

When('I filter by {string}') do |filter_name|
  # Show All / Incomplete live in the header's Actions menu — see
  # features/support/task_header_helpers.rb
  click_task_header_action(filter_name)
end

Then('I should see {string} message') do |content|
  expect(page).to have_content(content)
end


When('I create a new task and assign it to {string} with details {string}') do |assignee, details|
  click_on("New Task", match: :first)
  find(TASK_FORM_EDITOR).set(details)
  if assignee == "me"
    select @user.full_name, from: 'task_assigned_to_id'
  end
  click_on("Save")
  # Was sleep(2): wait for the create response - the assignment email the next step opens is sent
  # by the task's after_commit inside that request. Non-raising, like the sleep
  page.has_no_css?(TASK_FORM_EDITOR)
end

Then('an email should be sent to {string} with subject {string}') do |recipient, subject|
  email = (recipient == "me") ? @user.email : recipient
  open_email(email)
  expect(current_email.subject).to include(subject)
end
