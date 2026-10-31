# Security review 2026-10, findings C5 (stakeholder linked firm + merge) and C6 (user creation).
# Design: docs/security/security_review_2026_10.md, cards "C5 — Stakeholder linked firm + merge" and
# "C6 — User creation". Requests go through the rack_test driver wherever the request params are
# the thing under test; the merge runs InvestorMergeJob directly, as the merge screen enqueues it.
# @user / @entity / @fund and tenants / flagged_entity / "there is an LP ... of my fund" come from
# the shared and tenant_isolation_batch1 steps.

module SecurityC5C6Helpers
  # Stakeholders of my fund by the name they were created with, memoised before a merge renames
  # the old one to "... - Defunct/Inactive".
  def c5_stakeholder(name)
    @c5_stakeholders ||= {}
    @c5_stakeholders[name] ||= Investor.find_by!(entity_id: @entity.id, investor_name: name)
  end

  # The stakeholder's linked firm (the LP's own entity), read fresh from the DB.
  def c5_firm_of(name)
    c5_stakeholder(name).reload.investor_entity
  end

  # A grant with no user yet - the state InvestorAccess#update_user never leaves behind, but that
  # exists in prod (12 of 4,399 rows). save(validate: false) skips the before_validation that would
  # otherwise create the user straight away.
  def unclaimed_grant(investor, email)
    grant = InvestorAccess.new(entity_id: investor.entity_id, investor:, investor_entity_id: investor.investor_entity_id,
                               email:, first_name: "Un", last_name: "Claimed", approved: false)
    grant.save(validate: false)
    grant
  end

  # The fields the New User form posts to Users::RegistrationsController#create.
  def c6_user_form(email, password:, confirmation: password, entity_id: @user.entity_id)
    { user: { first_name: "New", last_name: "Person", email:, entity_id:,
              password:, password_confirmation: confirmation } }
  end
end
World(SecurityC5C6Helpers)

# ---- C5 setup ---------------------------------------------------------------------------------

Given('the LP {string} has a contact {string}') do |name, email|
  investor = c5_stakeholder(name)
  # A portal user of the LP's own firm, plus the approved grant that links them to the stakeholder
  user = FactoryBot.create(:user, entity: investor.investor_entity, email:, first_name: "Lata", last_name: "Contact")
  InvestorAccess.create!(investor:, entity_id: investor.entity_id, email: user.email, first_name: user.first_name,
                         last_name: user.last_name, approved: true, email_enabled: true)
end

Given('the firm of LP {string} is also a stakeholder of {string}') do |name, gp_name|
  firm = c5_firm_of(name)
  # Another GP knows the same real firm: the firm is no longer private to my fund
  FactoryBot.create(:investor, entity_id: tenants.fetch(gp_name).id, investor_entity_id: firm.id,
                               primary_email: firm.primary_email, investor_name: "#{name} at #{gp_name}", category: "LP")
end

Given('the LP {string} has a commitment in my fund') do |name|
  @c5_commitment = FactoryBot.create(:capital_commitment, fund: @fund, entity: @entity, investor: c5_stakeholder(name),
                                                          unit_type: "Series A", folio_id: "C5-#{SecureRandom.hex(3)}",
                                                          folio_currency: @fund.currency)
end

Given('there is an LP firm {string}') do |name|
  tenants[name] = flagged_entity(name, "Investor")
end

# ---- C5 actions -------------------------------------------------------------------------------

When('I update the LP {string} with the linked firm of {string} and city {string}') do |name, firm_name, city|
  page.driver.submit :patch, investor_path(c5_stakeholder(name), format: :json),
                     { investor: { investor_entity_id: tenants.fetch(firm_name).id, city: } }
end

When('I change the primary email of the LP {string} to {string}') do |name, email|
  page.driver.submit :patch, investor_path(c5_stakeholder(name), format: :json), { investor: { primary_email: email } }
end

When('I relink the LP {string} to the firm {string} in the admin panel') do |name, firm_name|
  page.driver.submit :patch, admin_investor_path(c5_stakeholder(name)),
                     { investor: { investor_entity_id: tenants.fetch(firm_name).id } }
end

When('I merge the LP {string} into {string}') do |old_name, new_name|
  old_investor = c5_stakeholder(old_name)
  new_investor = c5_stakeholder(new_name)
  # What the merge screen enqueues (InvestorsController#merge), run in-process
  InvestorMergeJob.perform_now(old_investor.id, new_investor.id, @user.id)
end

When('support runs the Entity merge of the LP {string} into {string}') do |old_name, new_name|
  # The support-only path EntityMerge.merge_entity takes (allow_cross_entity: true)
  Investor.merge(c5_stakeholder(old_name), c5_stakeholder(new_name), allow_cross_entity: true)
end

# ---- C5 checks --------------------------------------------------------------------------------

Then('the LP {string} is still linked to its own firm and has city {string}') do |name, city|
  investor = c5_stakeholder(name)
  original_firm_id = investor.investor_entity_id
  investor.reload
  expect(investor.investor_entity_id).to eq(original_firm_id)
  # The rest of the update still went through
  expect(investor.city).to eq(city)
end

Then('the LP {string} is linked to the firm with email {string}') do |name, email|
  expect(c5_firm_of(name).primary_email).to eq(email)
end

Then('the LP {string} is linked to the firm {string} and its grants follow') do |name, firm_name|
  firm = tenants.fetch(firm_name)
  expect(c5_firm_of(name).id).to eq(firm.id)
  # change_investor_entity cascaded the relink to the stakeholder's grants
  grants = InvestorAccess.where(investor_id: c5_stakeholder(name).id)
  expect(grants).to exist
  expect(grants.where.not(investor_entity_id: firm.id)).to be_none
end

Then('the contact {string} (still )belongs to the firm of {string}') do |email, name|
  expect(User.find_by!(email:).entity_id).to eq(c5_firm_of(name).id)
end

Then('the grant of contact {string} is now on the LP {string}') do |email, name|
  # The fund data merged even where the users stayed
  expect(InvestorAccess.where(email:, investor_id: c5_stakeholder(name).id)).to exist
end

Then('the contact {string} sees the commitment of {string}') do |email, _name|
  user = User.find_by!(email:)
  # The LP-side list scope: needs the user's firm to equal the stakeholder's linked firm
  expect(CapitalCommitment.for_investor(user).where(id: @c5_commitment.id)).to exist
end

Then('the merge alert warns {string}') do |text|
  alert = @captured_alerts.find { |a| a[:user_id] == @user.id && a[:message].include?("Merged") }
  expect(alert).not_to be_nil, "No merge alert was broadcast to the merging user"
  expect(alert[:message]).to include(text)
  expect(alert[:level].to_s).to eq("warning")
end

Then('the merge alert reports success without skipped contacts') do
  alert = @captured_alerts.find { |a| a[:user_id] == @user.id && a[:message].include?("Merged") }
  expect(alert).not_to be_nil, "No merge alert was broadcast to the merging user"
  expect(alert[:message]).not_to include("not moved")
  expect(alert[:level].to_s).to eq("success")
end

# ---- C6 setup ---------------------------------------------------------------------------------

Given('there is an unclaimed grant for {string} at {string} on an LP firm {string}') do |email, gp_name, firm_name|
  firm = tenants[firm_name] ||= flagged_entity(firm_name, "Investor")
  investor = FactoryBot.create(:investor, entity_id: tenants.fetch(gp_name).id, investor_entity_id: firm.id,
                                          primary_email: firm.primary_email, investor_name: firm_name, category: "LP")
  @c6_grant = unclaimed_grant(investor, email)
end

Given('there is an unclaimed grant for {string} at {string} on my firm') do |email, gp_name|
  investor = FactoryBot.create(:investor, entity_id: tenants.fetch(gp_name).id, investor_entity_id: @entity.id,
                                          primary_email: @entity.primary_email, investor_name: @entity.name, category: "LP")
  @c6_grant = unclaimed_grant(investor, email)
end

# ---- C6 actions -------------------------------------------------------------------------------

When('I post a new user {string} with password {string}') do |email, password|
  page.driver.submit :post, user_registration_path, c6_user_form(email, password:)
end

When('I post a new user {string} for the entity {string}') do |email, entity_name|
  page.driver.submit :post, user_registration_path,
                     c6_user_form(email, password: "Secret#2026x", entity_id: tenants.fetch(entity_name).id)
end

When('I post a new user {string} with mismatched passwords') do |email|
  page.driver.submit :post, user_registration_path,
                     c6_user_form(email, password: "Secret#2026x", confirmation: "Different#2026y")
end

# ---- C6 checks --------------------------------------------------------------------------------

Then('no user {string} exists') do |email|
  expect(User.where(email:)).to be_none
end

Then('the user {string} is created in my entity') do |email|
  expect(User.find_by!(email:).entity_id).to eq(@entity.id)
end

Then('the user {string} can log in with password {string}') do |email, password|
  created = User.find_by!(email:)
  # What Devise checks on the sign-in form
  expect(created.valid_password?(password)).to be true
  expect(created.active_for_authentication?).to be true
end

Then('the New User form is reopened without the password in the URL') do
  # The redirect still refills the form from the permitted fields ...
  expect(page).to have_current_path(%r{/users/new})
  expect(page.current_url).to include("first_name")
  # ... but never carries the password or its confirmation
  expect(page.current_url).not_to include("password")
end

Then('the unclaimed grant is still unclaimed') do
  expect(@c6_grant.reload.user_id).to be_nil
end

Then('the unclaimed grant is linked to the user {string}') do |email|
  expect(@c6_grant.reload.user_id).to eq(User.find_by!(email:).id)
end
