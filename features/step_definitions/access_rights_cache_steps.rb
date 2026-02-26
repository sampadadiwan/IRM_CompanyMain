Given('there is an entity {string}') do |kv|
  @entity = FactoryBot.create(:entity)
  key_values(@entity, kv)
  @entity.save!
end

Given('there is a fund {string} for the entity {string}') do |fund_kv, entity_kv|
  entity = Entity.find_by(name: entity_kv.split('=')[1])
  @fund = FactoryBot.create(:fund, entity: entity)
  key_values(@fund, fund_kv)
  @fund.save!
end

Given('there is an investor {string} for the entity {string} with investor_entity {string}') do |investor_kv, entity_kv, inv_entity_kv|
  entity = Entity.find_by(name: entity_kv.split('=')[1])
  inv_entity = Entity.find_by(name: inv_entity_kv.split('=')[1]) || FactoryBot.create(:entity, name: inv_entity_kv.split('=')[1])
  @investor = FactoryBot.create(:investor, entity: entity, investor_entity: inv_entity)
  key_values(@investor, investor_kv)
  @investor.save!
end

Given('there is a user {string} for the entity {string}') do |user_kv, entity_kv|
  entity = Entity.find_by(name: entity_kv.split('=')[1])
  @target_user = FactoryBot.create(:user, entity: entity, first_name: 'Test', last_name: 'User')
  key_values(@target_user, user_kv)
  @target_user.save!
end

Given('the user {string} has role {string}') do |email, role|
  user = User.find_by(email: email)
  user.add_role(role.to_sym)
  user.curr_role = role
  user.save!
  user.reset_access_rights_cache # Ensure initial state is clean
end

Given('there is an approved investor access for {string} and investor {string}') do |email, investor_name|
  user = User.find_by(email: email)
  investor = Investor.find_by(investor_name: investor_name)
  @investor_access = FactoryBot.create(:investor_access, user: user, investor: investor, entity: investor.entity, approved: true, email: user.email)
end

Given('there is an unapproved investor access for {string} and investor {string}') do |email, investor_name|
  user = User.find_by(email: email)
  investor = Investor.find_by(investor_name: investor_name)
  @investor_access = FactoryBot.create(:investor_access, user: user, investor: investor, entity: investor.entity, approved: false, email: user.email)
end

When('I grant {string} access to the fund for investor {string}') do |perms, investor_name|
  investor = Investor.find_by(investor_name: investor_name)
  @access_right = AccessRight.new(owner: @fund, entity: @fund.entity, access_to_investor_id: investor.id)
  perms.split(',').each { |p| @access_right.permissions.set(p.strip.to_sym) }
  @access_right.save!
end

When('I grant {string} access to the fund for user {string}') do |perms, email|
  user = User.find_by(email: email)
  @access_right = AccessRight.new(owner: @fund, entity: @fund.entity, user_id: user.id)
  perms.split(',').each { |p| @access_right.permissions.set(p.strip.to_sym) }
  @access_right.save!
end

When('I approve the investor access for {string}') do |email|
  ia = InvestorAccess.find_by(email: email)
  ia.update!(approved: true)
end

When('I create and approve an investor access for {string} and investor {string}') do |email, investor_name|
  investor = Investor.find_by(investor_name: investor_name)
  user = User.find_by(email: email)
  unless user
    user = FactoryBot.create(:user, email: email, entity: investor.investor_entity)
  end
  InvestorAccess.create!(user: user, investor: investor, entity: investor.entity, approved: true, email: email, first_name: 'Test', last_name: 'User')
end

When('I revoke the access right for investor {string} on the fund') do |investor_name|
  investor = Investor.find_by(investor_name: investor_name)
  AccessRight.where(owner: @fund, access_to_investor_id: investor.id).destroy_all
end

When('I delete the investor access for {string}') do |email|
  InvestorAccess.find_by(email: email).destroy
end

Then('the user {string} should have the fund in their access_rights_cache') do |email|
  user = User.find_by(email: email).reload
  cache = user.access_rights_cache
  found = false
  # Cache structure: { entity_id: { owner_type: { owner_id: "permissions, metadata" } } }
  cache&.each do |entity_id, types|
    if types["Fund"] && types["Fund"][@fund.id]
      found = true
      break
    end
  end
  expect(found).to be_truthy
end

Then('the user {string} should have the fund in their access_rights_cache with permissions {string}') do |email, perms|
  user = User.find_by(email: email).reload
  # get_cached_access_rights_permissions(entity_id, owner_type, owner_id)
  permissions, _metadata = user.get_cached_access_rights_permissions(@fund.entity_id, "Fund", @fund.id)

  expected_bits = 0
  perms.split(',').each do |p|
    # Bitmask check: this depends on the 'flag' gem implementation
    # But usually we can check if the bits are set.
    # Alternatively, use user.access_rights_cached_permissions.set?(p.to_sym)
    # but we need to call the getter first which sets it.
    expect(user.access_rights_cached_permissions.set?(p.strip.to_sym)).to be_truthy
  end
end

Then('the user {string} should NOT have the fund in their access_rights_cache') do |email|
  user = User.find_by(email: email).reload
  cache = user.access_rights_cache || {}
  found = false
  cache.each do |entity_id, types|
    if types["Fund"] && types["Fund"][@fund.id.to_s]
      found = true
      break
    end
  end
  expect(found).to be_falsey
end
