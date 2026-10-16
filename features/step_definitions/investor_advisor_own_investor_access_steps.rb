# An advisor keeps their own investor access - exercises ApplicationPolicy#permissioned_investor?,
# Investor#notification_users and User#home_persona the way the capital call notifiers and screens
# do. Worked examples: openspec/changes/fix-advisor-own-investor-access/report.md#verification
# @user / @entity (the advisor and their home) come from the shared login step.

module AdvisorOwnInvestorAccessHelpers
  # Recipients of every CapitalRemittanceNotifier event for this remittance.
  def remittance_recipient_ids(remittance)
    Noticed::Notification.joins(:event)
                         .where(noticed_events: { record_type: "CapitalRemittance", record_id: remittance.id })
                         .pluck(:recipient_id)
  end

  # An approved, email-enabled contact on an investor, the way the Users tab creates one.
  def approved_contact(investor, user: nil, email: nil)
    InvestorAccess.create!(investor:, user:, entity_id: investor.entity_id,
                           email: user&.email || email, first_name: user&.first_name || "Plain",
                           last_name: user&.last_name || "Contact", approved: true, email_enabled: true)
  end

  # A commitment plus a pending remittance on the shared capital call.
  def pending_remittance_for(investor)
    kyc = FactoryBot.create(:investor_kyc, entity: @fund_company, investor:, kyc_type: "individual", verified: true)
    commitment = FactoryBot.create(:capital_commitment, fund: @fund, entity: @fund_company, investor:, investor_kyc: kyc)
    remittance = FactoryBot.create(:capital_remittance, capital_call: @capital_call, fund: @fund, entity: @fund_company,
                                                        investor:, capital_commitment: commitment,
                                                        folio_id: commitment.folio_id,
                                                        folio_committed_amount_cents: commitment.folio_committed_amount_cents)
    # remittance_date is set from the call on a real run; the show page renders it.
    remittance.update_columns(status: "Pending", remittance_date: @capital_call.call_date)
    remittance
  end

  def entity_with_funds(name, entity_type)
    entity = FactoryBot.create(:entity, name:, entity_type:)
    entity.permissions.set(:enable_funds)
    entity.permissions.set(:enable_investor_advisors)
    entity.save!
    entity
  end

  # The InvestorAdvisor grant, saved the way the existing advisor steps do (ensure_user checks the
  # role, which the advisor already holds).
  def advisor_grant(entity, roles)
    grant = InvestorAdvisor.new(entity_id: entity.id, email: @user.email, allowed_roles: roles)
    # A switched advisor's feature flags come from the grant (UserEnabled#get_permissions), as
    # prod grant 485 does (permissions 232957 includes funds).
    grant.permissions.set(:enable_funds)
    grant.user = @user
    grant.save(validate: false)
    @advisor_grants ||= {}
    @advisor_grants[entity.name] = grant
  end

  def advisor
    @user.reload
  end

  def can_see?(user, record)
    Pundit.policy(user, record).show?
  end
end
World(AdvisorOwnInvestorAccessHelpers)

Given('the advisor is at home holding only the investor_advisor role') do
  # Prod user 2564 after InvestorAdvisor.revert into an Investor-type home: setup_defaults set
  # curr_role investor, then revert replaced every role with home_role_names = [investor_advisor].
  @entity.permissions.set(:enable_funds)
  @entity.save!
  @user.roles.delete_all
  @user.add_role(:investor_advisor)
  @user.update_columns(advisor_entity_id: @entity.id, advisor_entity_roles: nil, curr_role: "investor")
  expect(advisor.investor_advisor?).to be false
  expect(advisor.roles.map(&:name)).to eq(["investor_advisor"])
  expect(advisor.enable_funds).to be_truthy
end

Given("the advisor's home is an advisory firm with home roles {string}") do |roles|
  # A family office set up as an "Investor Advisor" firm that also invests itself: setup_defaults
  # puts curr_role = the first home role.
  names = roles.split(",").map(&:strip)
  @entity.update_columns(entity_type: "Investor Advisor")
  @user.roles.delete_all
  names.each { |role| @user.add_role(role) }
  @user.update_columns(entity_type: "Investor Advisor", advisor_entity_roles: roles, curr_role: names.first)
  expect(advisor.investor_advisor?).to be false
end

Given("the advisor and a plain contact are approved contacts of the advisor's own investor on the fund") do
  @fund_company.permissions.set(:enable_funds)
  @fund_company.permissions.set(:enable_investor_advisors)
  @fund_company.save!
  @own_investor = FactoryBot.create(:investor, entity_id: @fund_company.id, investor_entity_id: @entity.id,
                                               investor_name: @entity.name, category: "LP")
  @own_access = approved_contact(@own_investor, user: @user)
  @plain_access = approved_contact(@own_investor, email: "plain.#{SecureRandom.hex(4)}@example.com")
  @plain_user = @plain_access.user
  # Fund access is granted to the investor record, as in prod (AR 25164): no personal grant.
  AccessRight.create!(owner: @fund, access_to_investor_id: @own_investor.id, entity_id: @fund_company.id, notify: false)
  expect(@own_access.reload.is_investor_advisor).to be true
  expect(@plain_user.curr_role).to eq("investor")
  expect(AccessRight.where(owner: @fund).where.not(user_id: nil)).to be_empty
end

Given('there is an approved capital call on the fund with a pending remittance for the own investor') do
  @capital_call = FactoryBot.create(:capital_call, fund: @fund, entity: @fund_company, call_basis: "Upload",
                                                   name: "Call #{SecureRandom.hex(3)}")
  @capital_call.update_columns(approved: true, send_call_notice_flag: true)
  @own_remittance = pending_remittance_for(@own_investor)
end

Given('the advisor is an Investor Advisor for a client {string} who invests in the fund') do |name|
  # The commitment-page grant: it belongs to the client's entity, roles [investor], plus a personal
  # (user-level) grant on the fund in that entity and an approved contact row on the client.
  @client_entity = entity_with_funds(name, "Investor")
  @client_investor = FactoryBot.create(:investor, entity_id: @fund_company.id, investor_entity_id: @client_entity.id,
                                                  investor_name: name, category: "LP")
  @client_access = approved_contact(@client_investor, user: @user)
  AccessRight.create!(owner: @fund, access_to_investor_id: @client_investor.id, entity_id: @fund_company.id, notify: false)
  AccessRight.create!(owner: @fund, entity_id: @client_entity.id, user_id: @user.id, notify: false)
  advisor_grant(@client_entity, ["investor"])
  @client_remittance = pending_remittance_for(@client_investor)
end

Given('the advisor is an Investor Advisor for a client {string} who has no grant on the fund') do |name|
  @bare_client_entity = entity_with_funds(name, "Investor")
  advisor_grant(@bare_client_entity, ["investor"])
end

Given('the advisor is a Fund Advisor for the fund company with roles {string}') do |roles|
  # The Company menu → Advisors grant on the fund manager's own entity, with a personal grant on
  # the fund so the employee rule lets them see it once switched in.
  advisor_grant(@fund_company, roles.split(",").map(&:strip))
  AccessRight.create!(owner: @fund, entity_id: @fund_company.id, user_id: @user.id, notify: false)
end

Given('the advisor has switched into the client {string}') do |name|
  @advisor_grants.fetch(name).switch(@user)
  expect(advisor.investor_advisor?).to be true
  expect(advisor.entity.name).to eq(name)
end

Given('the advisor has switched into the fund company') do
  @advisor_grants.fetch(@fund_company.name).switch(@user)
  expect(advisor.investor_advisor?).to be true
  expect(advisor.entity_id).to eq(@fund_company.id)
end

Given('there is a second fund at the fund company granted only to the client') do
  @second_fund = FactoryBot.create(:fund, entity: @fund_company, name: "Second Fund")
  AccessRight.create!(owner: @second_fund, access_to_investor_id: @client_investor.id, entity_id: @fund_company.id, notify: false)
end

Given("the advisor's own contact row is tagged {string}") do |tag|
  @own_access.update_columns(tag_list: tag)
end

Given('the advisor also has a personal grant on the fund in their home entity') do
  AccessRight.create!(owner: @fund, entity_id: @entity.id, user_id: @user.id, notify: false)
end

Given('there is an advisory-firm user who is an approved contact of the client\'s investor') do
  firm = entity_with_funds("Advisory Firm #{SecureRandom.hex(3)}", "Investor Advisor")
  @firm_user = FactoryBot.create(:user, entity: firm)
  @firm_user.add_role(:investor_advisor)
  @firm_user.update_columns(advisor_entity_id: firm.id, advisor_entity_roles: "employee,investor_advisor",
                            curr_role: "employee")
  approved_contact(@client_investor, user: @firm_user)
  expect(@firm_user.reload.investor_advisor?).to be false
end

Given("all of the advisor's advisor grants are deleted") do
  InvestorAdvisor.where(user_id: @user.id).find_each(&:destroy)
  # The role survives, as it did in prod after InvestorAdvisor 484 was deleted.
  expect(advisor.has_cached_role?(:investor_advisor)).to be true
end

Given("the own investor's grant on the fund is removed") do
  AccessRight.where(owner: @fund, access_to_investor_id: @own_investor.id).find_each(&:destroy)
end

Given("the advisor's own contact row is unapproved") do
  @own_access.update_columns(approved: false)
end

Given("the advisor's own contact row is deleted") do
  @own_access.destroy
end

When('the capital call reminder is sent') do
  Noticed::Notification.delete_all
  expect(@capital_call.reload.reminder_capital_call).to be_nil
end

When('the call notice is sent for the own remittance') do
  Noticed::Notification.delete_all
  @own_remittance.reload.send_notification
end

When('the recipients for the own investor are computed while capturing the log') do
  log = StringIO.new
  original = Rails.logger
  Rails.logger = ActiveSupport::Logger.new(log)
  begin
    @own_investor.notification_users(@fund, with_tag: 'CapitalCall')
  ensure
    Rails.logger = original
  end
  @captured_log = log.string
end

Then('the advisor and the plain contact are notified for the own remittance') do
  expect(remittance_recipient_ids(@own_remittance)).to contain_exactly(@user.id, @plain_user.id)
end

Then('only the plain contact is notified for the own remittance') do
  expect(remittance_recipient_ids(@own_remittance)).to contain_exactly(@plain_user.id)
end

Then('nobody is notified for the own remittance') do
  expect(remittance_recipient_ids(@own_remittance)).to be_empty
end

Then('the advisor is notified exactly once for the own remittance') do
  expect(remittance_recipient_ids(@own_remittance).count(@user.id)).to eq(1)
end

Then('the advisor is notified for the client remittance') do
  expect(remittance_recipient_ids(@client_remittance)).to include(@user.id)
end

Then('the advisor can see the fund') do
  expect(can_see?(advisor, @fund)).to be true
end

Then('the advisor cannot see the fund') do
  expect(can_see?(advisor, @fund)).to be false
end

Then('the advisor can see the own remittance') do
  expect(can_see?(advisor, @own_remittance)).to be true
end

Then('the advisor cannot see the own remittance') do
  expect(can_see?(advisor, @own_remittance)).to be false
end

Then('the advisor can see the client remittance') do
  expect(can_see?(advisor, @client_remittance)).to be true
end

Then('the advisor cannot see the client remittance') do
  expect(can_see?(advisor, @client_remittance)).to be false
end

Then('the advisor cannot see the second fund') do
  expect(can_see?(advisor, @second_fund)).to be false
end

Then('the advisor is still a recipient for the client investor through their personal grant') do
  # By design (NOTIF-1..9): an advisor's client notices do not depend on where they are switched.
  expect(@client_investor.notification_users(@fund, with_tag: 'CapitalCall').map(&:id)).to include(@user.id)
end

Then('the advisor is not a recipient for the client investor on the second fund') do
  expect(@client_investor.notification_users(@second_fund, with_tag: 'CapitalCall').map(&:id)).not_to include(@user.id)
end

Then('the advisory-firm user cannot see the fund') do
  expect(can_see?(@firm_user.reload, @fund)).to be false
end

Then('the recipient preview for the own investor counts the advisor') do
  helper = Class.new { include FundsHelper }.new
  stats = helper.send(:calculate_user_access_stats, @fund, @own_investor.investor_accesses, tag: "CapitalCall")
  expect(stats[:approved_investor_access_ia].map(&:id)).to include(@own_access.id)
end

Then("the home persona's entity, roles and current role equal the user's after a real revert") do
  persona = advisor.home_persona
  expect(persona).to be_present
  snapshot = [persona.entity_id, persona.roles.map(&:name).sort, persona.curr_role.to_s]
  InvestorAdvisor.revert(@user, nil)
  reverted = advisor
  expect([reverted.entity_id, reverted.roles.map(&:name).sort, reverted.curr_role.to_s]).to eq(snapshot)
end

When('I visit the own remittance') do
  visit capital_remittance_path(@own_remittance)
end

Then('I am not denied access') do
  expect(page).not_to have_text("Access Denied")
end

Then("the log names the advisor's contact row and the fund") do
  expect(@captured_log).to include("InvestorAccess #{@own_access.id}")
  expect(@captured_log).to include("Fund #{@fund.id}")
end

# X6 — prod has advisors whose advisor_entity_id was never recorded (setup_defaults writes it only
# for an "Investor Advisor" home), so User#investor_advisor? stays false even while switched.
Given('the advisor is a legacy advisor with no recorded home') do
  @user.update_columns(advisor_entity_id: nil)
  expect(advisor.investor_advisor?).to be false
end

Given('the advisor is an Investor Advisor for a client {string} whose investor has a grant on the fund but gave the advisor no personal grant') do |name|
  client_entity = entity_with_funds(name, "Investor")
  client_investor = FactoryBot.create(:investor, entity_id: @fund_company.id, investor_entity_id: client_entity.id,
                                                 investor_name: name, category: "LP")
  approved_contact(client_investor, user: @user)
  AccessRight.create!(owner: @fund, access_to_investor_id: client_investor.id, entity_id: @fund_company.id, notify: false)
  advisor_grant(client_entity, ["investor"])
end

Given('the legacy advisor has switched into the client {string}') do |name|
  @advisor_grants.fetch(name).switch(@user)
  # The shape that fooled the old "at home" test: switched, yet investor_advisor? is false.
  expect(advisor.entity.name).to eq(name)
  expect(advisor.investor_advisor?).to be false
  expect(advisor.investor_advisor_id).to be_present
  expect(advisor.curr_role).to eq("investor")
end

# X7, X8, E18 — a client whose investor shares the fund, where the advisor is an approved contact
# (as advisor grants leave behind) but holds NO personal grant on this fund.
Given('the advisor is an approved contact of a client {string} who invests in the fund without giving the advisor a personal grant') do |name|
  entity = entity_with_funds(name, "Investor")
  investor = FactoryBot.create(:investor, entity_id: @fund_company.id, investor_entity_id: entity.id,
                                          investor_name: name, category: "LP")
  approved_contact(investor, user: @user)
  AccessRight.create!(owner: @fund, access_to_investor_id: investor.id, entity_id: @fund_company.id, notify: false)
  @other_clients ||= {}
  @other_clients[name] = { entity:, investor:, remittance: pending_remittance_for(investor) }
  expect(AccessRight.where(owner: @fund, user_id: @user.id, entity_id: entity.id)).to be_empty
end

Then('the advisor is not notified for the {string} remittance') do |name|
  expect(remittance_recipient_ids(@other_clients.fetch(name)[:remittance])).not_to include(@user.id)
end

Given("the advisor's own contact row has email turned off") do
  @own_access.update_columns(email_enabled: false)
end

# BaseNotifier skips email_enabled in the test env (see investor_kyc_notification_delivery.feature),
# so the delivery gate is asked directly, as that feature does.
def own_remittance_notification_for(user)
  Noticed::Notification.joins(:event)
                       .where(noticed_events: { record_type: "CapitalRemittance", record_id: @own_remittance.id })
                       .find_by!(recipient_id: user.id)
end

Then("the advisor's notification for the own remittance is not emailed") do
  expect(own_remittance_notification_for(@user).email_enabled).to be false
end

Then("the plain contact's notification for the own remittance is emailed") do
  expect(own_remittance_notification_for(@plain_user).email_enabled).to be true
end

Given('there is a deal at the fund company granted to the own investor') do
  [@entity, @fund_company].each do |entity|
    entity.permissions.set(:enable_deals)
    entity.save!
  end
  @fund_company.update_columns(currency: "INR", units: "Crores") if @fund_company.currency.blank?
  @deal = FactoryBot.create(:deal, entity: @fund_company)
  AccessRight.create!(owner: @deal, access_to_investor_id: @own_investor.id, entity_id: @fund_company.id, notify: false)
  expect(advisor.enable_deals).to be_truthy
end

Then('the advisor and the plain contact are recipients for the deal') do
  expect(@own_investor.notification_users(@deal).map(&:id)).to include(@user.id, @plain_user.id)
end

Given('the own investor has a KYC with no commitment') do
  @own_kyc = FactoryBot.create(:investor_kyc, entity: @fund_company, investor: @own_investor, kyc_type: "individual")
  expect(@own_kyc.capital_commitments).to be_empty
end

Then('the advisor can see the own KYC') do
  expect(can_see?(advisor, @own_kyc)).to be true
end

Then('the advisor is a recipient of the own KYC form') do
  expect(@own_kyc.notification_users.map(&:id)).to include(@user.id, @plain_user.id)
end

# E16 — prod has advisor accounts whose stored advisor_entity_roles leave investor_advisor out on
# an Investor-type home (e.g. "employee,investor"); revert then leaves them without the role.
Given('the advisor has reverted to a home whose stored roles leave out investor_advisor') do
  @user.roles.delete_all
  @user.add_role(:investor)
  @user.update_columns(advisor_entity_roles: "investor", curr_role: "investor", entity_id: @entity.id, investor_advisor_id: nil)
  expect(advisor.has_cached_role?(:investor_advisor)).to be false
end

When('I visit the client remittance') do
  visit capital_remittance_path(@client_remittance)
end

When('I visit the {string} remittance') do |name|
  visit capital_remittance_path(@other_clients.fetch(name)[:remittance])
end

When('I visit the second fund') do
  visit fund_path(@second_fund)
end

Then('I am told {string}') do |message|
  within("#page_alerts .alert-danger") { expect(page).to have_text(message) }
end

Then('I am told exactly {string}') do |message|
  expect(find("#page_alerts .alert-danger").text.strip).to eq(message)
end

When('I press {string} in the Access Denied alert') do |label|
  within("#page_alerts .alert-danger") { click_button(label) }
end

Then('I am on the client remittance') do
  expect(page).to have_current_path(capital_remittance_path(@client_remittance))
  expect(page).not_to have_text("Access Denied")
end

Then('the switch confirmation says {string}') do |text|
  expect(page).to have_text(text)
end

When('the advisor switches into {string} with return path {string}') do |name, return_to|
  page.driver.submit(:post, switch_investor_advisors_path, { id: @advisor_grants.fetch(name).id, return_to: })
end

Then('the switch does not redirect off-site') do
  expect(URI(page.current_url).host).not_to eq("evil.example.com")
  expect(advisor.entity_id).to eq(@client_entity.id)
end

Given('the client entity is renamed to {string}') do |name|
  @client_entity.update_columns(name:)
end

Then('the alert shows {string} as text, not markup') do |name|
  within("#page_alerts .alert-danger") do
    expect(page).to have_text("advisor for #{name}")
    expect(page).not_to have_css("b", text: "Bold")
    expect(page).to have_button("Switch to #{name}")
  end
end
