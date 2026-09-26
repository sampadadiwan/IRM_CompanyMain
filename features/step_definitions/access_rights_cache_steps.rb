# Step definitions for features/core/access_rights.feature
# Shared setup steps used across access_right scenarios.

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

Given('there is an entity {string}') do |kv|
  @entity = FactoryBot.create(:entity)
  key_values(@entity, kv)
  @entity.save!
end

Given('there is a neutral entity {string}') do |kv|
  @entity = FactoryBot.create(:entity, entity_type: 'Other')
  key_values(@entity, kv)
  @entity.save!
end

Given('there is a fund {string} for the entity {string}') do |fund_kv, entity_kv|
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  fund   = FactoryBot.create(:fund, entity: entity)
  key_values(fund, fund_kv)
  fund.save!
  # Track in a hash so scenarios with multiple funds can look them up by name
  @funds ||= {}
  @funds[fund.name] = fund
  @fund = fund
end

Given('there is a user {string} for the entity {string}') do |user_kv, entity_kv|
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  user   = FactoryBot.create(:user, entity: entity, first_name: 'Test', last_name: 'User')
  key_values(user, user_kv)
  user.save!
  @target_user = user
end

Given('the user {string} has role {string}') do |email, role|
  user = User.find_by!(email: email)
  user.add_role(role.to_sym)
  user.curr_role = role unless role == 'investor_advisor'
  user.save!
end

Given('there is an investor {string} for the entity {string} with investor_entity {string}') do |investor_kv, entity_kv, inv_entity_kv|
  entity     = Entity.find_by!(name: entity_kv.split('=').last)
  inv_entity = Entity.find_by(name: inv_entity_kv.split('=').last) ||
               FactoryBot.create(:entity, name: inv_entity_kv.split('=').last)
  investor = FactoryBot.create(:investor, entity: entity, investor_entity: inv_entity)
  key_values(investor, investor_kv)
  investor.save!
  @investors ||= {}
  @investors[investor.investor_name] = investor
  @investor = investor
end

Given('the investor {string} has category {string}') do |investor_name, category|
  investor = Investor.find_by!(investor_name: investor_name)
  investor.update!(category: category)
  @investors ||= {}
  @investors[investor_name] = investor
end

Given('there is an approved investor access for {string} and investor {string}') do |email, investor_name|
  user     = User.find_by!(email: email)
  investor = Investor.find_by!(investor_name: investor_name)
  @investor_access = FactoryBot.create(:investor_access,
    user: user, investor: investor, entity: investor.entity,
    approved: true, email: user.email)
end

Given('there is an unapproved investor access for {string} and investor {string}') do |email, investor_name|
  user     = User.find_by!(email: email)
  investor = Investor.find_by!(investor_name: investor_name)
  @investor_access = FactoryBot.create(:investor_access,
    user: user, investor: investor, entity: investor.entity,
    approved: false, email: user.email)
end

When('I create and approve an investor access for {string} and investor {string}') do |email, investor_name|
  investor = Investor.find_by!(investor_name: investor_name)
  user = User.find_by(email: email) ||
         FactoryBot.create(:user, email: email, entity: investor.investor_entity)
  InvestorAccess.create!(user: user, investor: investor, entity: investor.entity,
    approved: true, email: email, first_name: 'Test', last_name: 'User')
end

When('I approve the investor access for {string}') do |email|
  InvestorAccess.find_by!(email: email).update!(approved: true)
end

When('I unapprove the investor access for {string}') do |email|
  InvestorAccess.find_by!(email: email).update!(approved: false)
end

When('I delete the investor access for {string}') do |email|
  InvestorAccess.find_by!(email: email).destroy
end

When('I delete the investor advisor record for {string} from entity {string}') do |email, entity_kv|
  user   = User.find_by!(email: email)
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  InvestorAdvisor.find_by!(user: user, entity: entity).destroy
end

Given('the user {string} is an investor advisor for entity {string}') do |email, entity_kv|
  user   = User.find_by!(email: email)
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  InvestorAdvisor.create!(user: user, entity: entity, email: user.email)
end

# ---------------------------------------------------------------------------
# Access right grants
# ---------------------------------------------------------------------------

When('I grant {string} access to the fund for investor {string}') do |perms, investor_name|
  investor = Investor.find_by!(investor_name: investor_name)
  @access_right = AccessRight.new(owner: @fund, entity: @fund.entity,
    access_to_investor_id: investor.id)
  perms.split(',').each { |p| @access_right.permissions.set(p.strip.to_sym) }
  @access_right.save!
end

# Named-fund variant: use when @fund may have been overwritten by a subsequent fund creation
When('I grant {string} access to {string} for investor {string}') do |perms, fund_name, investor_name|
  fund     = (@funds || {})[fund_name] || Fund.find_by!(name: fund_name)
  investor = Investor.find_by!(investor_name: investor_name)
  ar = AccessRight.new(owner: fund, entity: fund.entity, access_to_investor_id: investor.id)
  perms.split(',').each { |p| ar.permissions.set(p.strip.to_sym) }
  ar.save!
end


When('I grant {string} access to the fund for investor {string} with metadata {string}') do |perms, investor_name, metadata|
  investor = Investor.find_by!(investor_name: investor_name)
  @access_right = AccessRight.new(owner: @fund, entity: @fund.entity,
    access_to_investor_id: investor.id, metadata: metadata)
  perms.split(',').each { |p| @access_right.permissions.set(p.strip.to_sym) }
  @access_right.save!
end

When('I grant {string} access to the fund for user {string}') do |perms, email|
  user = User.find_by!(email: email)
  @access_right = AccessRight.new(owner: @fund, entity: @fund.entity, user_id: user.id)
  perms.split(',').each { |p| @access_right.permissions.set(p.strip.to_sym) }
  @access_right.save!
end

When('I grant {string} access to {string} for user {string}') do |perms, fund_name, email|
  user = User.find_by!(email: email)
  fund = (@funds || {})[fund_name] || Fund.find_by!(name: fund_name)
  ar   = AccessRight.new(owner: fund, entity: fund.entity, user_id: user.id)
  perms.split(',').each { |p| ar.permissions.set(p.strip.to_sym) }
  ar.save!
end

When('I grant {string} access to the fund for category {string}') do |perms, category|
  # Mirror create_from_category: expand category to individual access_to_investor_id ARs.
  # access_to_category is never stored in production — the UI always expands to per-investor ARs.
  @fund.entity.investors.where(category: category.strip).find_each do |investor|
    ar = AccessRight.new(owner: @fund, entity: @fund.entity, access_to_investor_id: investor.id)
    perms.split(',').each { |p| ar.permissions.set(p.strip.to_sym) }
    ar.save!
    @access_right = ar
  end
end

When('I revoke the access right for investor {string} on the fund') do |investor_name|
  investor = Investor.find_by!(investor_name: investor_name)
  AccessRight.where(owner: @fund, access_to_investor_id: investor.id).destroy_all
end

# ---------------------------------------------------------------------------
# Investor Advisor setup
# ---------------------------------------------------------------------------

# Creates an InvestorAdvisor record AND calls switch(), changing the user's entity_id
# to the advising entity. This mirrors the real advisor workflow.
# Builds the grant and switches the advisor into the host entity in one step.
#
# 'employee' is included in allowed_roles so that after switch() the user has
# has_cached_role?(:employee) = true, which FundBasePolicy::Scope requires to call for_employee.
#
# The advisor's own user must already live in an entity_type=Investor Advisor entity, otherwise
# advisor_entity_id is never recorded, InvestorAdvisor refuses to create the grant, and
# User#investor_advisor? would stay false even after the switch.
Given('the advisor {string} is switched into entity {string}') do |email, entity_kv|
  user   = User.find_by!(email: email)
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  ia = InvestorAdvisor.new(user: user, entity: entity, email: user.email,
         allowed_roles: ['employee', 'investor_advisor'])
  # Once the advisor is switched in, User#get_permissions reads THIS grant's permissions
  # instead of the user's own, so a grant with none leaves every enable_* flag false and any
  # policy opening with user.enable_funds (FundPolicy#show?) denies on that first condition,
  # before an access right is ever looked at - a denial that reads as an access-rights failure
  # but is really a missing module flag. Mirror the user's own permissions so these scenarios
  # exercise the access right, which is what they are here to test.
  User.permissions.keys.each { |permission| ia.permissions.set(permission) }
  ia.save!
  ia.switch(user)
  user.reload
end

# Creates an InvestorAdvisor record WITHOUT switching — the user stays in their home entity.
# Use this to test that unswitched advisors are blocked.
Given('there is an investor advisor record for {string} on entity {string}') do |email, entity_kv|
  user   = User.find_by!(email: email)
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  InvestorAdvisor.create!(user: user, entity: entity, email: user.email,
    allowed_roles: ['investor_advisor'])
  # No switch — user.entity_id remains their home entity
end

# ---------------------------------------------------------------------------
# Capital commitment setup
# ---------------------------------------------------------------------------

Given('the fund has a capital commitment from investor {string}') do |investor_name|
  investor = Investor.find_by!(investor_name: investor_name)
  @commitments ||= {}
  commitment = FactoryBot.create(:capital_commitment, fund: @fund, investor: investor,
    entity: @fund.entity)
  @commitments[investor_name] = commitment
  @capital_commitment = commitment
end

# ---------------------------------------------------------------------------
# Policy assertions (single-record layer)
# ---------------------------------------------------------------------------

Then('the user {string} should be allowed {string} on the fund') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @fund).send("#{action.strip}?")
    expect(result).to be_truthy,
      "expected #{email} to be allowed #{action} on fund #{@fund.name}, but was denied"
  end
end

Then('the user {string} should be denied {string} on the fund') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @fund).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on fund #{@fund.name}, but was allowed"
  end
end

Then('the user {string} should be denied {string} on {string}') do |email, actions, fund_name|
  user = User.find_by!(email: email)
  fund = (@funds || {})[fund_name] || Fund.find_by!(name: fund_name)
  actions.split(',').each do |action|
    result = Pundit.policy(user, fund).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on fund #{fund_name}, but was allowed"
  end
end

Then('the user {string} should be allowed {string} on the capital commitment') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @capital_commitment).send("#{action.strip}?")
    expect(result).to be_truthy,
      "expected #{email} to be allowed #{action} on capital commitment, but was denied"
  end
end

Then('the user {string} should be denied {string} on the capital commitment') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @capital_commitment).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on capital commitment, but was allowed"
  end
end

Then('the user {string} should be denied {string} on the capital commitment of {string}') do |email, actions, investor_name|
  user       = User.find_by!(email: email)
  commitment = (@commitments || {})[investor_name]
  actions.split(',').each do |action|
    result = Pundit.policy(user, commitment).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on #{investor_name}'s commitment, but was allowed"
  end
end

# ---------------------------------------------------------------------------
# Metadata assertions
# ---------------------------------------------------------------------------

Then('the user {string} should pass metadata check {string} on the fund') do |email, metadata|
  user = User.find_by!(email: email)
  result = Pundit.policy(user, @fund).permissioned_investor?(metadata)
  expect(result).to be_truthy,
    "expected #{email} to pass metadata check '#{metadata}' but failed"
end

Then('the user {string} should fail metadata check {string} on the fund') do |email, metadata|
  user = User.find_by!(email: email)
  result = Pundit.policy(user, @fund).permissioned_investor?(metadata)
  expect(result).to be_falsey,
    "expected #{email} to fail metadata check '#{metadata}' but passed"
end

# ---------------------------------------------------------------------------
# Scope assertions (list-query layer)
# ---------------------------------------------------------------------------

Then('the fund scope for user {string} should include {string}') do |email, fund_name|
  user   = User.find_by!(email: email)
  fund   = (@funds || {})[fund_name] || Fund.find_by!(name: fund_name)
  scoped = Pundit.policy_scope!(user, Fund)
  expect(scoped.where(id: fund.id).exists?).to be_truthy,
    "expected fund '#{fund_name}' to appear in scope for #{email}, but it did not"
end

Then('the fund scope for user {string} should not include {string}') do |email, fund_name|
  user   = User.find_by!(email: email)
  fund   = (@funds || {})[fund_name] || Fund.find_by!(name: fund_name)
  scoped = Pundit.policy_scope!(user, Fund)
  expect(scoped.where(id: fund.id).exists?).to be_falsey,
    "expected fund '#{fund_name}' NOT to appear in scope for #{email}, but it did"
end
