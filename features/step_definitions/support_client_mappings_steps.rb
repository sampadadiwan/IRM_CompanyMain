Given("a user exists with role {string}") do |role|
  entity = FactoryBot.create(:entity)
  @user = FactoryBot.create(:user, entity: entity)
  @user.add_role(role.to_sym)
end

Given("an entity exists with employees") do
  @entity = FactoryBot.create(:entity)
  @employees = FactoryBot.create_list(:user, 2, entity: @entity)
  @entity.reload
end

Given("a support client mapping exists linking the user to the entity") do
  @mapping = FactoryBot.create(:support_client_mapping, user: @user, entity: @entity)
end

When("I call to_s on the support client mapping") do
  @result = @mapping.to_s
end

Then("I should see the support mapping {string}") do |expected|
  expect(@result).to eq(expected.gsub("<user>", @user.to_s).gsub("<entity>", @entity.to_s))
end

Given("the mapping is disabled") do
  @mapping.enabled = false
  @mapping.save.should be true
end

Given("the mapping is enabled") do
  @mapping.enabled = true
  @mapping.save.should be true
end

When("I enable the mapping") do
  @mapping.enable_support
end

When("I call disable_expired") do
  SupportClientMapping.disable_expired
end

When("I call switch") do
  @mapping.switch
end

When("I call revert") do
  @mapping.revert
end

When("I check the mapping status") do
  @status = @mapping.status
end

When("the user reverts") do
  @mapping.revert
end

Then("the mapping should be enabled") do
  expect(@mapping.reload.enabled).to be true
end

Then("the entity should have enable_support permission") do
  expect(@mapping.entity.permissions).to be_set(:enable_support)
end

Then("all employees should have enable_support set to true") do
  @mapping.entity.reload.employees.each do |emp|
    expect(emp.enable_support).to be true
  end
end

Then("the mapping should be disabled") do
  expect(@mapping.reload.enabled).to be false
end

Then("the entity should not have enable_support permission") do
  expect(@mapping.entity.permissions).not_to be_set(:enable_support)
end

Then("the user's entity should be updated to the mapped entity") do
  expect(@mapping.user.reload.entity).to eq(@entity)
end

Then("the user should gain the company_admin role") do
  expect(@mapping.user.has_role?(:company_admin)).to be true
end

Given("the user has switched") do
  @mapping.enable_support
  @mapping.switch
end

Then("the user's entity should be reset to the original") do
  orig_entity_id = @mapping.user.json_fields["orig_entity_id"]
  expect(@mapping.user.entity_id).to eq(orig_entity_id)
end

Then("the user should have the support role") do
  expect(@mapping.user.has_role?(:support)).to be true
end

Then("the company_admin role should be removed") do
  expect(@mapping.user.has_role?(:company_admin)).to be false
end

Then("it should be {string}") do |expected|
  expect(@mapping.status).to eq(expected)
end

Given("the mapping has user_emails {string}") do |emails|
  @mapping.update(user_emails: emails)
end

Given("enable_user_login is true") do
  @mapping.update(enable_user_login: true)
end

When("I call allow_login_as with {string}") do |email|
  @result = @mapping.allow_login_as(email)
end

Then("it should return true") do
  expect(@result).to be true
end

Then("it should return false") do
  expect(@result).to be false
end

Given("it has an end_date in the past") do
  @mapping.update(end_date: Date.yesterday, enabled: true)
end