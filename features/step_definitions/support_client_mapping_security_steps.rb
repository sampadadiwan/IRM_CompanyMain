# Step definitions for support_client_mapping_security_fixes.feature
# Each step is tied to a specific security finding from the review.

# ── Finding 1 helpers ────────────────────────────────────────────────────────

Then("the user should be back in their original entity") do
  expect(@user.reload.entity_id).to eq(@orig_entity_id)
end

# ── Finding 2 / role assertions ───────────────────────────────────────────────

Then("the user should not have the {string} role") do |role|
  expect(@user.reload.has_role?(role.to_sym)).to be false
end

Then("the user should have the {string} role") do |role|
  expect(@user.reload.has_role?(role.to_sym)).to be true
end

# ── Finding 3 helpers ────────────────────────────────────────────────────────

Given("the user is granted the {string} role while switched") do |role|
  @user.add_role(role.to_sym)
end

Given("the {string} role is then revoked by an admin") do |role|
  @user.remove_role(role.to_sym)
end

Then("the orig_entity_id should be cleared from json_fields") do
  expect(@user.reload.json_fields['orig_entity_id']).to be_nil
end

Then("the orig_roles should be cleared from json_fields") do
  expect(@user.reload.json_fields['orig_roles']).to be_nil
end

# ── Finding 4 helpers ────────────────────────────────────────────────────────

Given("a super user exists") do
  super_entity = FactoryBot.create(:entity)
  @super_user = FactoryBot.create(:user, entity: super_entity)
  # Stub super? and has_cached_role? so the policy sees this as a super user
  # without needing to persist a forbidden :super role (forbid_bad_role blocks it).
  @super_user.define_singleton_method(:super?) { true }
  @super_user.define_singleton_method(:has_cached_role?) { |r| r.to_sym == :super }
end

When("the super user checks the switch policy for the support user's mapping") do
  @policy_result = SupportClientMappingPolicy.new(@super_user, @mapping).switch?
end

Then("the switch should be denied for the super user") do
  expect(@policy_result).to be false
end

When("the super user checks the revert policy for the support user's mapping") do
  @policy_result = SupportClientMappingPolicy.new(@super_user, @mapping).revert?
end

Then("the revert should be denied for the super user") do
  expect(@policy_result).to be false
end

When("the mapped user checks the switch policy") do
  # @entity must have enable_support set for switch? to return true
  @entity.permissions.set(:enable_support)
  @entity.save
  @policy_result = SupportClientMappingPolicy.new(@user, @mapping).switch?
end

Then("the switch should be permitted for the mapped user") do
  expect(@policy_result).to be true
end

When("the mapped user checks the revert policy") do
  @policy_result = SupportClientMappingPolicy.new(@user, @mapping).revert?
end

Then("the revert should be permitted for the mapped user") do
  expect(@policy_result).to be true
end

# ── Finding 5 helpers ────────────────────────────────────────────────────────

Given("enable_user_login is false") do
  @mapping.update(enable_user_login: false)
end

Given("the mapping has no user_emails restriction") do
  @mapping.update(user_emails: "")
end

# ── Finding 6 helpers ────────────────────────────────────────────────────────

Given("a second mapping exists for the user that is disabled") do
  @disabled_mapping = FactoryBot.create(:support_client_mapping,
                                        user:       @user,
                                        entity:     FactoryBot.create(:entity),
                                        enabled:    false,
                                        end_date:   Date.yesterday)
end

When("I resolve the scope as the support user") do
  @scope = SupportClientMappingPolicy::Scope.new(@user, SupportClientMapping).resolve
end

Then("I should see only the enabled mapping") do
  expect(@scope).to include(@mapping)
end

Then("I should not see the disabled mapping") do
  expect(@scope).not_to include(@disabled_mapping)
end
