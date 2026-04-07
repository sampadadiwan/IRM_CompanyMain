Given("a user exists with role {string}") do |role|
  entity = FactoryBot.create(:entity)
  @user = FactoryBot.create(:user, entity: entity)
  @user.add_role(role.to_sym)
  @support_user = @user if role == "support"
  @super_user = @user if role == "super"
  # Force super? to return true if role is super
  if role == "super"
    @user.define_singleton_method(:super?) { true }
    @user.define_singleton_method(:has_cached_role?) { |r| r.to_sym == :super }
  end
end

Given("an entity exists with employees") do
  @entity = FactoryBot.create(:entity)
  @employees = FactoryBot.create_list(:user, 2, entity: @entity)
  @entity.reload
end

Given("a support client mapping exists linking the user to the entity") do
  @mapping = FactoryBot.create(:support_client_mapping, user: @user, entity: @entity)
end

Given("a support client mapping exists linking the support user to the entity") do
  @mapping = FactoryBot.create(:support_client_mapping, user: @support_user, entity: @entity)
end

When("I call to_s on the support client mapping") do
  @result = @mapping.to_s
end

Then("I should see the support mapping {string}") do |expected|
  expect(@result).to eq(expected.gsub("<user>", @user.to_s).gsub("<entity>", @entity.to_s))
end

Given("the mapping is disabled") do
  @mapping.disable_support
end

Given("the mapping is enabled") do
  @mapping.enable_support
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
  expect(@mapping.entity.reload.permissions).to be_set(:enable_support)
end

Then("all employees should have enable_support set to true") do
  @mapping.entity.reload.employees.each do |emp|
    expect(emp.reload.enable_support).to be true
  end
end

Then("the mapping should be disabled") do
  expect(@mapping.reload.enabled).to be false
end

Then("the entity should not have enable_support permission") do
  expect(@mapping.entity.reload.permissions).not_to be_set(:enable_support)
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

# New steps from full_steps

Given("I am logged in as the super user") do
  @user = @super_user || FactoryBot.create(:user).tap { |u| u.add_role(:super) }
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

Given("I am logged in as the support user") do
  @user = @support_user || FactoryBot.create(:user).tap { |u| u.add_role(:support) }
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

Given("I am logged in as the employee user") do
  @user = FactoryBot.create(:user).tap { |u| u.add_role(:employee) }
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

When("I create a support client mapping for the support user and entity") do
  @mapping = SupportClientMapping.create!(user: @support_user, entity: @entity, end_date: Date.tomorrow, enabled: true)
  @mapping.enable_disable
end

Then("the mapping should be created successfully") do
  expect(@mapping).to be_persisted
end

When("I update the mapping's end_date to tomorrow") do
  @mapping.update!(end_date: Date.tomorrow)
end

Then("the mapping should be updated successfully") do
  expect(@mapping.reload.end_date).to eq(Date.tomorrow)
end

Then("the end_date should be tomorrow") do
  expect(@mapping.reload.end_date).to eq(Date.tomorrow)
end

When("I delete the support client mapping") do
  @mapping.destroy!
end

When("the SCM daily morning job runs") do
  DailyMorningJob.perform_now
end

When("I manually disable the mapping") do
  @mapping.disable_support
end

Given("I have switched to the client entity context") do
  @mapping.switch
end

Then("the mapping should no longer exist") do
  expect(SupportClientMapping.exists?(@mapping.id)).to be false
end

Given("the mapping's end_date is in the past") do
  @mapping.update!(end_date: Date.yesterday, enabled: true)
end

Given("the mapping's end_date was 2 weeks ago") do
  @mapping.update!(end_date: Date.today - 2.weeks, enabled: false)
end

When("I switch to the client entity context") do
  @mapping.switch
end

Then("my current entity should be the client entity") do
  expect(@user.reload.entity_id).to eq(@entity.id)
end

Then("I should have the {string} role") do |role|
  expect(@user.reload.has_role?(role.to_sym)).to be true
end

Then("I should not have the {string} role") do |role|
  expect(@user.reload.has_role?(role.to_sym)).to be false
end

Then("my original state should be cached in json_fields") do
  expect(@user.reload.json_fields['orig_entity_id']).to be_present
end

When("I revert to my original entity context") do
  @mapping.revert
end

Then("my current entity should be my original entity") do
  expect(@user.reload.entity_id).to eq(@user.json_fields['orig_entity_id'])
end

Then("my original state should be cleared from json_fields") do
  expect(@user.reload.entity_id).to eq(@user.json_fields['orig_entity_id'])
end

When("I check my mapping status") do
  @status = @mapping.status
end

When("I check if I can login as {string}") do |email|
  @result = @mapping.allow_login_as(email)
end

When("I view the support client mappings index") do
  @mappings = SupportClientMappingPolicy::Scope.new(@user, SupportClientMapping).resolve
end

Then("I should see all mappings in the system") do
  expect(@mappings).to include(@mapping)
end

Then("I should only see my own mappings") do
  expect(@mappings).to include(@mapping)
  expect(@mappings).not_to include(@other_mapping) if @other_mapping
end

Then("I should be denied access") do
  policy = SupportClientMappingPolicy.new(@user, @mapping || SupportClientMapping)
  if @mapping.nil?
    expect(policy.index?).to be false
  else
    expect(policy.show?).to be false
  end
end

When("I try to switch to the client entity context") do
  @policy = SupportClientMappingPolicy.new(@user, @mapping)
  @can_switch = @policy.switch?
end

Then("I should be denied access to switch") do
  expect(@can_switch).to be false
end

Then("calling revert should raise an error {string}") do |error_message|
  expect { @mapping.revert }.to raise_error(RuntimeError, error_message)
end

Given("another user exists with role {string}") do |role|
  @other_user = FactoryBot.create(:user, entity: FactoryBot.create(:entity))
  @other_user.add_role(role.to_sym)
end

Given("another support client mapping exists linking that user to the same entity") do
  @other_mapping = FactoryBot.create(:support_client_mapping, user: @other_user, entity: @entity)
end

Given("both mappings are enabled") do
  @mapping.enable_support
  @other_mapping.enable_support
end

When("I disable the first mapping") do
  @mapping.disable_support
end

Then("the first mapping should be disabled") do
  expect(@mapping.reload.enabled).to be false
end

Then("the entity should still have enable_support permission") do
  expect(@entity.reload.permissions).to be_set(:enable_support)
end

Then("all employees should still have enable_support set to true") do
  @entity.reload.employees.each do |emp|
    expect(emp.reload.enable_support).to be true
  end
end

Given("the user's original entity information is lost") do
  @user.json_fields.delete("orig_entity_id")
  @user.save!
end

Given("the entity's support permission is manually disabled") do
  @entity.permissions.unset(:enable_support)
  @entity.save!
end

Then("calling switch should raise an error {string}") do |error_message|
  expect { @mapping.switch }.to raise_error(RuntimeError, error_message)
end

When("the user's support role is removed") do
  @user.remove_role(:support)
end

Then("the user should still be able to revert via the mapping") do
  expect { @mapping.revert }.not_to raise_error
  expect(@user.reload.entity_id).to eq(@user.json_fields["orig_entity_id"])
end

When("I delete the mapping") do
  @mapping.destroy!
end

Then("all employees should have enable_support set to false") do
  @entity.reload.employees.each do |emp|
    expect(emp.reload.enable_support).to be false
  end
end
