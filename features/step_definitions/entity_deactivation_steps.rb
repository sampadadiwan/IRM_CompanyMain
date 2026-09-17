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

When('the deactivation job for {string} runs the way Sidekiq runs it') do |name|
  entity = Entity.find_by(name: name)
  # update_column flips the flag without firing the after_commit cascade, so the job below is
  # the only thing that runs — exactly like the queued job picking the record up later.
  entity.update_column(:active, false)

  # features/support/env.rb pins Chewy to :bypass for the whole suite, which short-circuits
  # every index callback and hides a missing strategy. A Sidekiq worker starts on :base
  # instead, which raises Chewy::UndefinedUpdateStrategy the moment an indexed model is saved,
  # so :base is what the job has to survive.
  Chewy.strategy(:base) do
    EntityDeactivationJob.perform_now(entity_id: entity.id)
  end
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
