# Step 1: Login as user in entity
Given('I am logged in as a user in entity {string}') do |entity_name|
  @entity = FactoryBot.create(:entity, name: entity_name)
  @user = FactoryBot.create(:user, entity: @entity)
  @investor_user = @user
  steps %(
    Given I login as the investor user
  )
end

# Step 2: Another user in same entity creates a template
Given('another user in entity {string} has created a template {string}') do |entity_name, template_name|
  entity = Entity.find_by(name: entity_name) || FactoryBot.create(:entity, name: entity_name)
  other_user = FactoryBot.create(:user, entity: entity)
  @template = FactoryBot.create(:investment_criteria_template,
    name: template_name,
    entity: entity,
    created_by_user: other_user
  )
end

# Step 3: Visit templates page (JSON request to avoid needing HTML template)
When('I visit the investment criteria templates page') do
  visit investment_criteria_templates_path(format: :json)
end

# Step 4: Check template is visible in JSON response
Then('I should see template {string}') do |template_name|
  # Extract JSON from the <pre> tag if wrapped in HTML (browser rendering)
  body = page.body
  if body.include?('<pre>') && body.include?('</pre>')
    body = body.match(%r{<pre>(.*?)</pre>}m)[1]
  end
  json_response = JSON.parse(body)
  template_names = json_response.map { |t| t['name'] }
  expect(template_names).to include(template_name)
end
