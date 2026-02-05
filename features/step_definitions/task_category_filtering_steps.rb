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
  select category, from: 'category_filter'
  # Wait for reload
  sleep 1
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
