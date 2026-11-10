Given('there are following tasks for the entity:') do |table|
  table.hashes.each do |row|
    Task.create!(entity: @user.entity, details: row['details'], category: row['category'], user: @user, owner: @user.entity)
  end
end

When('I go to the tasks page') do
  visit tasks_path
end

When('I go to the dashboard page') do
  visit root_path
end

When('I select {string} from the category filter dropdown') do |category|
  # Wait for the filter's auto-submit reload - was sleep 1 (page_load_helpers.rb)
  wait_for_page_after(timeout: 1) { select category, from: 'category_filter' }
end

When('I click on {string} in the sidebar') do |link_text|
  within '#sidebarnav' do
    click_on link_text
  end
end

Then('I should see {string} in the {string} stat card') do |count, subtitle|
  within ".card[data-task-stat-title='#{subtitle}']" do
    expect(page).to have_content(count)
  end
end

# The category select on the task form — asserted through the New Task form
# rather than the model so a category missing from the dropdown is caught.
Then('{string} should be offered as a task category') do |category|
  click_on('New Task', match: :first)
  expect(page).to have_select('task_category', with_options: [category])
end
