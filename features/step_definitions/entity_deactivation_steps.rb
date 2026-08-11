# Steps for features/core/entity_deactivation.feature
# @entity / @user come from the shared "Im logged in as a user ... for an entity" step.

Given('the entity has an active employee {string}') do |email|
  @employee = FactoryBot.create(:user, entity: @entity, email: email, active: true)
end

Given('the entity has an approved investor access for {string}') do |email|
  # An InvestorAccess needs an Investor, which in turn needs the LP's own (investor) entity —
  # InvestorAccess#update_user creates the portal user under that investor entity.
  investor_entity = FactoryBot.create(:entity, name: "LP Entity for #{email}", entity_type: "Investor",
                                               primary_email: email)
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: investor_entity,
                                          investor_name: investor_entity.name, primary_email: email)
  @investor_access = FactoryBot.create(:investor_access, entity: @entity, investor: investor,
                                                         email: email, first_name: "Lp", last_name: "User",
                                                         approved: true)
end

When('I confirm the entity deactivation') do
  # The confirmation checkbox is `required`, so the form will not submit without it
  check 'confirm_deactivate'
  click_on 'Deactivate Entity'
end

When('the entity {string} is deactivated directly') do |name|
  # Bypasses the UI to prove the cascade is driven by the model, not by the controller
  Entity.find_by(name: name).update!(active: false)
end

When('the entity {string} is activated directly') do |name|
  Entity.find_by(name: name).update!(active: true)
end

Then('the entity {string} should be deactivated') do |name|
  expect(Entity.find_by(name: name).reload.active).to be false
end

Then('the investor access for {string} should not be approved') do |email|
  expect(InvestorAccess.find_by(email: email).reload.approved).to be false
end

Then('the employee {string} should be inactive') do |email|
  expect(User.find_by(email: email).reload.active).to be false
end
