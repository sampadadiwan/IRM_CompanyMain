Given("a user exists") do
  entity = FactoryBot.create(:entity)
  @user = FactoryBot.create(:user, entity: entity)
end

Given("an entity exists") do
  @entity = FactoryBot.create(:entity)
end

Given("the mapping status is {string}") do |status|
  @mapping.update(enabled: true)
  if status == "Switched"
    # simulate switched by setting json fields
    @mapping.user.update(json_fields: { "orig_entity_id" => 0, "orig_roles" => ["support"] })
    allow(@mapping).to receive(:status).and_return("Switched")
  else
    allow(@mapping).to receive(:status).and_return("Reverted")
  end
end

Given("the entity has enable_support set to true") do
  @entity.permissions.set(:enable_support)
  @entity.save
end

When("I check the policy for switch") do
  @policy = SupportClientMappingPolicy.new(@user, @mapping)
  @result = @policy.switch?
end

When("I check the policy for revert") do
  @policy = SupportClientMappingPolicy.new(@user, @mapping)
  @result = @policy.revert?
end

When("I resolve the policy scope") do
  @scope = SupportClientMappingPolicy::Scope.new(@user, SupportClientMapping.all).resolve
end

Then("it should permit") do
  expect(@result).to be true
end

Then("it should deny") do
  expect(@result).to be false
end

Given("the user is a super user") do
  allow(@user).to receive(:super?).and_return(true)
end

Given("the user is not a super user") do
  allow(@user).to receive(:super?).and_return(false)
end

Then("it should return all mappings") do
  expect(@scope).to match_array(SupportClientMapping.all)
end

Then("it should return only the mappings for that user") do
  expect(@scope).to match_array(SupportClientMapping.where(user_id: @user.id))
end