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
      sleep 0.5 # poll interval of this wait loop - kept
    end
    expect(val).to include(content)
  end
end

# --- fix-portfolio-dashboard-widgets: labels, helper text, retired settings, whole-number IDs ---

Given('a dashboard widget {string} exists for {string} with metadata {string}') do |widget_name, dashboard_name, metadata|
  @widget = DashboardWidget.create!(widget_name:, dashboard_name:, entity: @entity, tags: "test", size: "Medium", metadata:)
end

def metadata_field_group(key)
  find_field("metadata_#{key}", visible: :all).find(:xpath, "./ancestor::div[contains(@class,'form-group')][1]")
end

Then('the field {string} should have the label {string}') do |key, label|
  expect(metadata_field_group(key).find("label").text.strip).to eq(label)
end

Then('the field {string} should have helper text containing {string}') do |key, text|
  expect(metadata_field_group(key)).to have_css(".form-text", text:)
end

Then('there should be no field for {string}') do |key|
  expect(page).to have_no_field("metadata_#{key}")
end

When('I type {string} into the field {string}') do |text, key|
  find_field("metadata_#{key}").send_keys(text)
end

When('I paste {string} into the field {string}') do |text, key|
  field = find_field("metadata_#{key}")
  page.execute_script(<<~JS, field, text)
    const [el, text] = arguments
    const data = new DataTransfer()
    data.setData("text", text)
    el.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }))
  JS
end

Then('the field {string} should contain {string}') do |key, value|
  expect(find_field("metadata_#{key}").value).to eq(value)
end

When('I save the widget') do
  click_on("Save")
  expect(page).to have_content("successfully updated")
end

Then('the saved metadata of the {string} widget should contain {string}') do |name, text|
  expect(DashboardWidget.find_by(widget_name: name).reload.metadata.to_s).to include(text)
end

# --- fix-portfolio-dashboard-widgets-2: stats Fields multi-select, Default currency ---

Given('the entity has currency {string} and an exchange rate from {string} to {string}') do |currency, from, to|
  @entity.update!(currency:)
  ExchangeRate.create!(entity_id: @entity.id, from:, to:, rate: 83, as_of: Time.zone.today)
end

When('I pick {string} in the multi-select {string}') do |option, key|
  metadata_field_group(key).find(".select2-selection").click
  find(".select2-results__option", text: option, exact_text: true).click
end

When('I remove {string} from the multi-select {string}') do |option, key|
  metadata_field_group(key).find(".select2-selection__choice[title='#{option}'] .select2-selection__choice__remove").click
end

Then('the multi-select {string} should show {string}') do |key, names|
  chips = metadata_field_group(key).all(".select2-selection__choice").map { |chip| chip[:title] }
  expect(chips).to eq(names.split(",").map(&:strip))
end

Then('the field {string} should offer {string}') do |key, names|
  offered = find_field("metadata_#{key}").all("option").map(&:value).compact_blank
  expect(offered).to match_array(names.split(",").map(&:strip))
end

# U1 — the blank option of a pick-list reads what leaving it empty means ("Default" for Units)
Then('the field {string} should have the empty option {string}') do |key, label|
  expect(find_field("metadata_#{key}").first("option").text).to eq(label)
end

Then('the saved metadata of the {string} widget should not contain {string}') do |name, text|
  expect(DashboardWidget.find_by(widget_name: name).reload.metadata.to_s).not_to include(text)
end

When('I go to the new dashboard widget page') do
  visit new_dashboard_widget_path
end

When('I choose the dashboard {string} and widget type {string}') do |dashboard_name, widget_name|
  select(dashboard_name, from: "dashboard_name")
  select(widget_name, from: "widget_name")
  expect(page).to have_field("metadata_fields", visible: :all)
end
