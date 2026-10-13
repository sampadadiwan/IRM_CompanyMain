# Edge-case steps for the evergreen investor portal, GP screens, notifications and closed-ended
# compatibility (investor_portal.feature, gp_screens.feature, notifications.feature, regression.feature).
# Worked examples E160–E179, X100–X108 — openspec/changes/open-ended-funds/design.md#worked-examples

# ---- People, access and switches ----

# An outside user (another entity) is the investor's "Managed by" employee — written directly, so the
# investor carries an RM that cannot be a recipient (EvergreenRecipients#relationship_manager)
Given('{string} is managed by {string} of another entity {string}') do |investor_name, first_name, entity_name|
  # The outside user is created by the shared step and registered under @evergreen_people
  steps %(Given there is a user "#{first_name}" of another entity "#{entity_name}")
  rm = evergreen_person(first_name)
  inv = Investor.find_by!(entity_id: @fund.entity_id, investor_name:)
  inv.update_columns(managed_by_user_id: rm.id)
  expect(inv.reload.managed_by.entity_id).not_to eq(@fund.entity_id)
end

Given('the employee {string} is deactivated') do |name|
  user = evergreen_person(name)
  user.update_columns(active: false)
  expect(user.reload.active?).to be(false)
end

# An employee of the entity with no access right on the fund (and not a company admin)
Given('there is an employee {string} without access to the fund') do |name|
  user = FactoryBot.create(:user, entity: @fund.entity, first_name: name)
  user.add_role(:employee)
  user.update_columns(curr_role: "employee")
  expect(FundPolicy.new(user.reload, @fund).show?).to be(false)
end

# An employee who can update this fund only (fund access right with the update permission)
Given('there is an employee {string} who can update only the fund') do |name|
  user = FactoryBot.create(:user, entity: @fund.entity, first_name: name)
  user.add_role(:employee)
  user.update_columns(curr_role: "employee")
  ar = AccessRight.new(entity_id: @fund.entity_id, owner: @fund, user_id: user.id, access_type: "Fund", notify: false)
  ar.permissions.set(:update)
  ar.save!
  # Sanity: he can update this fund, and no other fund of the entity is visible to him
  expect(FundPolicy.new(user.reload, @fund).update?).to be(true)
end

When('the user {string} signs in') do |name|
  evergreen_fresh_login(evergreen_person(name))
end

# The entity-level evergreen switch turned off after funds were made evergreen
Given('the entity has evergreen funds switched off') do
  entity = @fund.entity.reload
  entity.permissions.unset(:enable_evergreen_funds)
  entity.save!(validate: false)
  @fund.reload.reset_evergreen_cache
  expect(@fund.evergreen?).to be(false)
end

Given('{string} has no portal users') do |name|
  inv = Investor.find_by!(entity_id: @fund.entity_id, investor_name: name)
  expect(inv.approved_investor_accesses.exists?).to be(false)
end

# ---- Alerts and emails ----

Then('{string} should get the alert {string} {int} times') do |name, text, count|
  user = evergreen_person(name)
  title = evergreen_alert_title(text)
  subjects = evergreen_mails_to(user).map(&:subject)
  # Email and in-app copies are counted separately: each send produces one of each
  expect(subjects.count(title)).to eq(count), "#{name} got #{subjects.inspect}"
  expect(evergreen_inapp_messages(user).count(title)).to eq(count)
end

Then('exactly {int} email(s) with subject {string} should have been sent') do |count, subject|
  expect(ActionMailer::Base.deliveries.count { |m| m.subject == subject }).to eq(count)
end

# ---- Copy from fund ----

# An evergreen fund of ANOTHER entity, with enabled Evergreen templates
Given('there is an evergreen fund {string} of another entity {string} with evergreen notifications for {string}') do |name, entity_name, keys|
  other = FactoryBot.create(:entity, name: entity_name, entity_type: "Investment Fund")
  admin = FactoryBot.create(:user, entity: other)
  admin.add_role(:company_admin)
  fund = FactoryBot.create(:fund, entity: other, name:, currency: "INR", unit_types: "A")
  # make_fund_evergreen also switches evergreen on for that entity
  make_fund_evergreen(fund, admin)
  keys.split(",").map(&:strip).each do |key|
    CustomNotification.create!(entity_id: other.id, owner: fund, for_type: "Evergreen", email_method: key, enabled: true,
                               subject: "#{name}: #{key.humanize}", body: "<p>#{name} wording.</p>")
  end
end

# A CLOSED-ENDED fund of the same entity that nevertheless carries Evergreen templates
Given('the closed-ended fund {string} of the entity has evergreen notifications for {string}') do |name, keys|
  current = @fund
  steps %(Given there is a fund "name=#{name};currency=INR;unit_types=A" for the entity)
  closed = @fund
  @fund = current
  expect(closed.reload.evergreen?).to be(false)
  keys.split(",").map(&:strip).each do |key|
    CustomNotification.create!(entity_id: closed.entity_id, owner: closed, for_type: "Evergreen", email_method: key, enabled: true,
                               subject: "#{name}: #{key.humanize}", body: "<p>#{name} wording.</p>")
  end
end

# A direct POST of the copy form as the signed-in user (@user), naming any fund by name
When('I try to copy the notifications from {string} directly') do |source_name|
  source = Fund.find_by!(name: source_name)
  session = evergreen_http_session(@user)
  session.post evergreen_notification_copy_path(@fund), params: { from_fund_id: source.id }
  @copy_location = session.response.location.to_s
end

Then('the copy should have been refused') do
  # A successful copy lands on the fund's Notifications tab; a refusal does not
  expect(@copy_location).not_to include("evergreen-notifications-tab")
  expect(@copy_location).not_to include("sign_in")
end

# ---- Investor portal ----

Then('the Redeem button of folio {string} should be enabled') do |folio|
  expect(page).to have_css("a#redeem_#{folio.parameterize}", text: "Redeem")
end

# A document on the folio as the dealing-date generator leaves it (owner_tag "Generated")
Given('folio {string} has an {word} generated document {string}') do |folio, state, name|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  Document.create!(entity_id: @fund.entity_id, owner: cc, name:, owner_tag: "Generated", approved: state == "approved",
                   user: @gp_user || @user, file: Rails.public_path.join("sample_uploads", "SignedDoc.pdf").open("rb"))
end

# An investor posting the order form directly, naming a folio by its number
When('{string} tries to place a {string} order of {string} units on folio {string} directly') do |name, kind, units, folio|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  @orders_before = DealingOrder.count
  session = evergreen_http_session(@investor_users.fetch(name))
  session.post evergreen_orders_path(@fund), params: { dealing_order: { kind:, unit_type: "A", units:, capital_commitment_id: cc.id } }
end

Then('no order should be placed on folio {string}') do |folio|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  expect(DealingOrder.where(capital_commitment_id: cc.id).count).to eq(0)
end

Then('{string} should have no orders') do |name|
  inv = Investor.find_by!(entity_id: @fund.entity_id, investor_name: name)
  expect(DealingOrder.where(investor_id: inv.id).count).to eq(0)
end

# GP screens an investor (or outsider) might type into the address bar
EVERGREEN_DIRECT_PAGES = {
  "unit register" => :evergreen_investors_path, "order book" => :evergreen_orders_path,
  "dealing dates" => :evergreen_dealing_dates_path, "fees" => :evergreen_fees_path
}.freeze

When('I request the evergreen {string} page directly') do |page_name|
  evergreen_visit(send(EVERGREEN_DIRECT_PAGES.fetch(page_name), @fund))
end

Then('I should not see the unit register') do
  expect(page).not_to have_css("#unit_register")
end

Then('I should not see the evergreen tabs') do
  expect(page).not_to have_css("#evergreen_tabs")
end

Then('I should not see the evergreen investor page') do
  expect(page).not_to have_css("#evergreen_investor_page")
end

# ---- Unit register ----

Then('the register row of folio {string} should show the hard lock-up badge {string}') do |folio, date|
  within("#register_#{folio.parameterize}") do
    # Hard lock-up: red badge with the lock icon and the date the lock ends
    expect(page).to have_css(".badge.bg-danger-subtle", text: date)
    expect(page).to have_css(".badge .ti-lock")
  end
end

Then('the register row of folio {string} should show no lock-up badge') do |folio|
  within("#register_#{folio.parameterize}") do
    expect(page).not_to have_css(".ti-lock")
    expect(page).not_to have_css(".ti-lock-open")
  end
end

Then('the register row of folio {string} should show {string} units queued') do |folio, units|
  within("#register_#{folio.parameterize}") do
    expect(page).to have_css(".badge .ti-clock")
    expect(page).to have_css(".badge", text: units)
  end
end

# Download the .xlsx through a signed-in HTTP session and keep the rows by folio
When('I download the unit register') do
  session = evergreen_http_session(@user)
  session.get evergreen_investors_path(@fund, format: :xlsx)
  expect(session.response.status).to eq(200)
  path = Rails.root.join("tmp/evergreen_register_#{SecureRandom.hex(4)}.xlsx")
  File.binwrite(path, session.response.body)
  rows = Roo::Spreadsheet.open(path.to_s, extension: :xlsx).sheet(0).to_a
  header = rows.first
  @register_download = rows.drop(1).to_h { |r| [r[header.index("Folio")], header.zip(r).to_h] }
end

Then('the downloaded unit register should have:') do |table|
  table.hashes.each do |expected|
    row = @register_download.fetch(expected["Folio"])
    # Numbers compared as decimals, dates as ISO text, blanks as empty
    expect(row["Units"].to_d.round(4)).to eq(expected["Units"].to_d)
    expect(row["Queued units"].to_d).to eq(expected["Queued units"].to_d)
    expect(row["Locked until"].to_s).to eq(expected["Locked until"].to_s)
  end
  expect(@register_download.size).to eq(table.hashes.size)
end

# ---- Closed-ended compatibility ----

Given('the closed-ended fund has a distribution') do
  @closed_distribution = FactoryBot.create(:capital_distribution, fund: @closed_fund, entity: @closed_fund.entity)
end

When('I open the closed-ended call') do
  evergreen_visit(capital_call_path(@closed_call))
end

Then('I should be on the closed-ended call page') do
  # Not redirected to the evergreen settlement page
  expect(page).to have_current_path(capital_call_path(@closed_call))
  expect(page).to have_content("Call 1")
end

When('I open the closed-ended distribution') do
  evergreen_visit(capital_distribution_path(@closed_distribution))
end

Then('I should be on the closed-ended distribution page') do
  expect(page).to have_current_path(capital_distribution_path(@closed_distribution))
  expect(page).not_to have_content("Redemption settlement")
end
