Given('I am logged in as an admin') do
  @entity = FactoryBot.create(:entity)
  @user = FactoryBot.create(:user, entity: @entity)
  @user.add_role(:admin)
  steps %(
    And I am signed in as the current user
  )
end

Given('a dashboard widget {string} exists for {string}') do |widget_name, dashboard_name|
  @widget = DashboardWidget.create!( 
                               widget_name: widget_name, 
                               dashboard_name: dashboard_name, 
                               entity: @entity,
                               tags: "test",
                               size: "Medium")
end

Given('a widget {string} exists with help {string}') do |name, help|
  @widget = DashboardWidget.create!( 
                               widget_name: name, 
                               dashboard_name: "Fund Dashboard", 
                               metadata_help: help,
                               entity: @entity,
                               tags: "test",
                               size: "Medium")
end

When('I go to the edit page for the {string} widget') do |name|
  widget = DashboardWidget.find_by(widget_name: name)
  visit edit_dashboard_widget_path(widget)
end

Then('I should see the {string} section') do |title|
  expect(page).to have_content(title)
end

When('I fill in metadata {string} with {string}') do |label, value|
  fill_in(label, with: value)
end

When('I check metadata {string}') do |label|
  check(label)
end

Then('I should see a field for {string}') do |label|
  # Try both ID and label
  begin
    expect(page).to have_field("metadata_#{label}")
  rescue RSpec::Expectations::ExpectationNotMetError
    expect(page).to have_field(label)
  end
end

Then('the {string} field should have placeholder {string}') do |label, placeholder|
  field = find_field("metadata_#{label}")
  expect(field[:placeholder]).to eq(placeholder)
end

Then('the {string} hidden field should contain {string}') do |field_name, content|
  # Use wait to ensure JS has updated the field
  using_wait_time(10) do
    # The field is readonly, so we check its value
    # We use a loop to wait for the value to change if needed
    start_time = Time.now
    val = ""
    while Time.now - start_time < 5
      val = find_field("dashboard_widget_#{field_name}", visible: false).value
      break if val.include?(content)
      sleep 0.5
    end
    expect(val).to include(content)
  end
end
