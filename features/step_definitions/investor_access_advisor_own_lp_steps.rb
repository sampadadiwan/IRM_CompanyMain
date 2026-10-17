# A GP can add an advisor as a contact of the advisor's own LP record - exercises
# InvestorAccess#block_investor_advisor_from_ui through the Users form (H1) and through the same
# flag the form sets (disallow_investor_advisor), as InvestorAccessesController#create does.
# Worked examples: openspec/changes/fix-advisor-add-own-lp-contact/report.md#verification
# @user / @entity (the GP company admin) and @fund come from the shared steps.

module AdvisorOwnLpHelpers
  def lp_entities
    @lp_entities ||= {}
  end

  def lp_investors
    @lp_investors ||= {}
  end

  def entity_named(name, entity_type)
    lp_entities[name] ||= FactoryBot.create(:entity, name:, entity_type:)
  end

  # An LP record of the GP for `entity`, with access to the fund granted to the investor.
  def lp_record_for(entity)
    lp_investors[entity.name] ||= begin
      investor = FactoryBot.create(:investor, entity_id: @entity.id, investor_entity_id: entity.id,
                                              investor_name: entity.name, category: "LP")
      AccessRight.create!(owner: @fund, access_to_investor_id: investor.id, entity_id: @entity.id, notify: false)
      investor
    end
  end

  # A user holding the investor_advisor role whose recorded home is `home`, as setup_defaults /
  # InvestorAdvisor#ensure_advisor_home record it.
  def advisor_at(email, home, curr_role)
    user = FactoryBot.create(:user, email:, entity: home)
    user.roles.delete_all
    user.add_role(:investor_advisor)
    user.update_columns(advisor_entity_id: home.id, curr_role:)
    user.reload
  end
end
World(AdvisorOwnLpHelpers)

Given('there is an advisor {string} whose home is the investor entity {string}') do |email, name|
  advisor_at(email, entity_named(name, "Investor"), "investor")
end

Given('there is an advisor {string} whose home is the fund company {string}') do |email, name|
  advisor_at(email, entity_named(name, "Investment Fund"), "employee")
end

Given('the investor entity {string} is an LP of the fund') do |name|
  lp_record_for(lp_entities.fetch(name))
end

Given('the fund company {string} is an LP of the fund') do |name|
  lp_record_for(lp_entities.fetch(name))
end

Given('there is an investor entity {string} that is an LP of the fund') do |name|
  lp_record_for(entity_named(name, "Investor"))
end

Given('{string} is switched into a client {string}') do |email, name|
  # E1: the user's current entity is the client's, the recorded home stays their own firm.
  client = entity_named(name, "Investor")
  User.find_by!(email:).update_columns(entity_id: client.id)
end

Given('{string} has no recorded advisor home') do |email|
  User.find_by!(email:).update_columns(advisor_entity_id: nil)
end

Given('there is a plain user {string} in the investor entity {string}') do |email, name|
  user = FactoryBot.create(:user, email:, entity: entity_named(name, "Investor"))
  expect(user.has_cached_role?(:investor_advisor)).to be false
end

When('I add {string} from the Users form of the {string} stakeholder') do |email, name|
  investor = lp_investors.fetch(name)
  user = User.find_by!(email:)
  visit new_investor_access_path('investor_access[investor_id]': investor.id, 'investor_access[entity_id]': @entity.id)
  fill_in 'investor_access_email', with: user.email
  fill_in 'investor_access_first_name', with: user.first_name
  fill_in 'investor_access_last_name', with: user.last_name
  check 'investor_access_approved'
  click_on "Save"
end

# The same object InvestorAccessesController#create builds, including the UI-only flag.
When('{string} is added to {string} through the Users form path') do |email, name|
  investor = lp_investors.fetch(name)
  user = User.find_by!(email:)
  @contact_row = InvestorAccess.new(investor:, entity_id: investor.entity_id, email: user.email,
                                    first_name: user.first_name, last_name: user.last_name,
                                    approved: true, granted_by: @user.id)
  @contact_row.disallow_investor_advisor = true
  @contact_saved = @contact_row.save
end

Then('the page says {string}') do |text|
  expect(page).to have_text(text)
end

Then('{string} is an approved contact of {string} flagged as an advisor') do |email, name|
  row = lp_investors.fetch(name).investor_accesses.find_by!(email:)
  expect(row.approved).to be true
  # The flag still follows the role, so the advisor fund-grant cleanup runs on delete (E4).
  expect(row.is_investor_advisor).to be true
end

Then('the contact row is saved') do
  expect(@contact_saved).to be(true), "refused: #{@contact_row.errors.full_messages.to_sentence}"
end

Then('the contact row is refused with {string}') do |message|
  expect(@contact_saved).to be false
  expect(@contact_row.errors.full_messages.to_sentence).to include(message)
end

Then('{string} is a capital call recipient for {string} on the fund') do |email, name|
  user = User.find_by!(email:)
  expect(lp_investors.fetch(name).notification_users(@fund, with_tag: 'CapitalCall').map(&:id)).to include(user.id)
end

Given('{string} has a personal grant on the fund in {string}') do |email, name|
  investor = lp_investors.fetch(name)
  # The cleanup only looks at funds the investor is committed to.
  FactoryBot.create(:capital_commitment, fund: @fund, entity: @entity, investor:,
                                         investor_kyc: FactoryBot.create(:investor_kyc, entity: @entity, investor:, kyc_type: "individual"))
  @personal_grant_user = User.find_by!(email:)
  AccessRight.create!(owner: @fund, entity_id: lp_entities.fetch(name).id, user_id: @personal_grant_user.id, notify: false)
end

When('the contact row is deleted') do
  # Loaded fresh, as the destroy request does: the in-memory row from the create step holds an
  # investor whose capital_commitments were cached before the commitment above existed.
  InvestorAccess.find(@contact_row.id).destroy
end

Then('{string} has no personal grant on the fund in {string}') do |email, name|
  user = User.find_by!(email:)
  expect(AccessRight.where(owner: @fund, entity_id: lp_entities.fetch(name).id, user_id: user.id)).to be_empty
end
