# Steps for features/fund/evergreen/notifications.feature (and E64 in regression.feature).
# Recipients are resolved by name: an investor name means every portal user of that investor; any
# other name is an employee (or advisor / outside user) created by these steps or the login step.
# Worked examples H40–H56, E52–E65, X21–X25 — openspec/changes/open-ended-funds/design.md#worked-examples

# ---- Helpers ----

# Users behind a name: an investor's portal users, a named outside user, else an employee of the fund's entity
def evergreen_people(name)
  return @investor_user_lists[name] if @investor_user_lists&.key?(name)
  return [@investor_users[name]] if @investor_users&.key?(name)
  return [@evergreen_people[name]] if @evergreen_people&.key?(name)

  user = User.where(entity_id: (@fund || @user).entity_id, first_name: name).order(:id).last
  raise "No user called #{name}" unless user

  [user]
end

def evergreen_person(name)
  evergreen_people(name).first
end

# Emails delivered to one user
def evergreen_mails_to(user)
  ActionMailer::Base.deliveries.select { |m| Array(m.to).include?(user.email) }
end

def evergreen_mail_body(mail)
  part = mail.html_part || mail.text_part || mail
  part.body.decoded.dup.force_encoding("UTF-8")
end

# In-app team alerts (EvergreenOpsNotifier) for one user
def evergreen_inapp_messages(user)
  Noticed::Notification.where(recipient: user, type: "EvergreenOpsNotifier::Notification").map(&:message)
end

# Team alert subjects and in-app messages are "<fund>: <text>"
def evergreen_alert_title(text)
  "#{@fund.name}: #{text}"
end

# An employee of the logged-in user's entity; company admins see every fund
def evergreen_employee(name, roles: %w[company_admin], tags: nil)
  user = FactoryBot.create(:user, entity: @user.entity, first_name: name)
  roles.each { |r| user.add_role(r.to_sym) }
  user.update_columns(curr_role: "employee", tag_list: tags)
  user.reload
end

# A signed-in HTTP session (no browser) for a user, to post forms directly
def evergreen_http_session(user)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post "/users/sign_in", params: { user: { email: user.email, password: "password" } }
  session
end

# ---- People and roles ----

# 'the user is tagged {string}' is in weekly_task_digest_steps.rb; '{string} is managed by {string}'
# (Investor#managed_by) is in kpi_report_journey_steps.rb

Given('there is an employee {string}') do |name|
  evergreen_employee(name)
end

Given('there is an employee {string} tagged {string}') do |name, tags|
  evergreen_employee(name, tags:)
end

# A plain employee who sees the fund only through a user access right on it
Given('there is an employee {string} tagged {string} with access to the fund through its access list') do |name, tags|
  user = evergreen_employee(name, roles: [], tags:)
  AccessRight.create!(entity_id: @fund.entity_id, owner: @fund, user_id: user.id, access_type: "Fund", notify: false)
  expect(FundPolicy.new(user.reload, @fund).show?).to be(true)
end

Given('{string} is removed from the fund access list') do |name|
  user = evergreen_person(name)
  AccessRight.where(owner: @fund, user_id: user.id).find_each(&:destroy)
  expect(FundPolicy.new(user.reload, @fund).show?).to be(false)
end

# An investor of the fund with several portal users (all on its access list)
Given('{string} is an investor of the fund with {string} portal users') do |name, count|
  steps %(Given there is an existing investor "name=#{name}" with "#{count}" users)
  AccessRight.create!(owner: @fund, access_type: "Fund", metadata: "Investor", access_to_investor_id: @investor.id, entity_id: @fund.entity_id)
  evergreen_approved_kyc(@investor)
  @investor_users ||= {}
  @investor_user_lists ||= {}
  @investor_user_lists[name] = @investor.investor_accesses.map(&:user)
  @investor_users[name] = @investor_user_lists[name].first
end

# An advisor user of an advisory firm, on the investor's access list (approved), with no right yet
# to see the investor's orders
Given('{string} has an advisor {string} from {string}') do |investor_name, advisor_name, firm|
  inv = Investor.find_by!(entity_id: @fund.entity_id, investor_name:)
  firm_entity = FactoryBot.create(:entity, name: firm, entity_type: "Investor Advisor")
  advisor = FactoryBot.create(:user, entity: firm_entity, first_name: advisor_name)
  InvestorAccess.create!(investor: inv, user: advisor, entity_id: inv.entity_id, first_name: advisor.first_name,
                         last_name: advisor.last_name, email: advisor.email, approved: true)
  expect(advisor.reload.has_cached_role?(:investor_advisor)).to be(true)
  @evergreen_people ||= {}
  @evergreen_people[advisor_name] = advisor
end

# The advisor is granted the fund for the investor (as features/step_definitions/access_rights.rb does)
Given('the advisor {string} is allowed to see the orders of {string}') do |advisor_name, investor_name|
  inv = Investor.find_by!(entity_id: @fund.entity_id, investor_name:)
  advisor = evergreen_person(advisor_name)
  AccessRight.create!(entity_id: inv.investor_entity_id, owner: @fund, user_id: advisor.id, metadata: "Investor Advisor", notify: false)
end

Given('there is a user {string} of another entity {string}') do |name, entity_name|
  other = FactoryBot.create(:entity, name: entity_name, entity_type: "Investment Fund")
  user = FactoryBot.create(:user, entity: other, first_name: name)
  user.add_role(:company_admin)
  @evergreen_people ||= {}
  @evergreen_people[name] = user
end

# ---- Orders, NAVs, payments ----

# A portal order: placed by the investor's own user through the service, source "portal"
When('{string} places a {string} order {string} in the portal received {string}') do |name, kind, values, received|
  inv = Investor.find_by!(entity_id: @fund.entity_id, investor_name: name)
  kv = evergreen_kv(values)
  folio = @fund.capital_commitments.find_by(folio_id: kv.delete(:folio)) if kv[:folio]
  params = kv.merge(kind:, investor_id: inv.id, capital_commitment_id: folio&.id, unit_type: kv[:class] || "A", received_at: received)
  result = DealingOrderCreate.call(fund: @fund, params: params.except(:class), current_user: @investor_users.fetch(name), source: "portal")
  raise "order failed: #{result[:errors]}" unless result.success?

  @last_order = result[:order]
end

When('{string} drafts the NAV for {string}') do |name, date|
  result = FundNavBuilder.call(fund: @fund.reload, nav_date: Date.parse(date), current_user: evergreen_person(name))
  raise "draft failed: #{result[:errors]}" unless result.success?
end

When('{string} approves the class {string} NAV for {string}') do |name, unit_type, date|
  nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  result = FundNavApprove.call(fund_nav: nav, current_user: evergreen_person(name))
  raise "approve failed: #{result[:errors]}" unless result.success?
end

# The verified remittance is saved again (a reference correction) — replays the settlement hook
When('the subscription payment of {string} is saved again with a corrected reference') do |name|
  rem = evergreen_order_of(name, "subscription").capital_remittance.reload
  expect(rem.verified).to be(true)
  rem.notes = "Reference corrected to UTR998877"
  rem.save!(validate: false)
end

# ---- Switches ----

Given('the fund notification {string} is switched {string}') do |key, state|
  setting = @fund.evergreen_fund_setting
  setting.update!(notifications: setting.notifications.to_h.merge(key => state == "on"))
end

# Raw JSON as stored, e.g. '{"payment_reminder": false}'
Given('the fund notifications are saved as {string}') do |json|
  @fund.evergreen_fund_setting.update!(notifications: JSON.parse(json))
end

Given('the fund notifications were never saved') do
  @fund.evergreen_fund_setting.update_columns(notifications: nil)
end

# ---- Daily check ----

When('the daily notification check runs on {string}') do |date|
  steps %(Given today is "#{date}")
  EvergreenNotificationsJob.perform_now
end

When('the daily notification check runs again') do
  EvergreenNotificationsJob.perform_now
end

# X25: one fund's daily check raises; errors sent to the developer inbox are captured
Given('the daily check of {string} raises an error') do |fund_name|
  @reported_errors = []
  allow(ExceptionNotifier).to receive(:notify_exception) { |error, *rest| @reported_errors << [error, rest] }
  allow(EvergreenAlerts).to receive(:daily).and_wrap_original do |original, setting, **kw|
    raise "Simulated daily check failure" if setting.fund.name == fund_name

    original.call(setting, **kw)
  end
end

Then('the error in the daily check of {string} should have been reported') do |fund_name|
  reports = @reported_errors.map { |error, rest| "#{error.class} #{error.message} #{rest.inspect}" }
  expect(reports.any? { |r| r.include?("Simulated daily check failure") && r.include?(fund_name) }).to be(true),
                                                                                                       "expected an error report naming #{fund_name}, got #{reports.inspect}"
end

# ---- Email and alert assertions ----

Then('{string} should receive {int} email(s) with subject {string}') do |name, count, subject|
  evergreen_people(name).each do |user|
    subjects = evergreen_mails_to(user).map(&:subject)
    expect(subjects.count(subject)).to eq(count), "#{user.email} got #{subjects.inspect}"
  end
end

Then('{string} should receive no email with subject {string}') do |name, subject|
  evergreen_people(name).each do |user|
    expect(evergreen_mails_to(user).map(&:subject)).not_to include(subject)
  end
end

Then('the email {string} to {string} should contain {string}') do |subject, name, text|
  evergreen_people(name).each do |user|
    mail = evergreen_mails_to(user).rfind { |m| m.subject == subject }
    expect(mail).to be_present, "#{user.email} got no email #{subject}"
    expect(evergreen_mail_body(mail)).to include(text)
  end
end

# A team alert arrives by email and in-app
Then('{string} should get the alert {string}') do |name, text|
  user = evergreen_person(name)
  title = evergreen_alert_title(text)
  expect(evergreen_mails_to(user).map(&:subject)).to include(title)
  expect(evergreen_inapp_messages(user)).to include(title)
end

Then('{string} should get the alert {string} once') do |name, text|
  user = evergreen_person(name)
  title = evergreen_alert_title(text)
  subjects = evergreen_mails_to(user).map(&:subject)
  expect(subjects.count(title)).to eq(1), "#{name} got #{subjects.inspect}"
  expect(evergreen_inapp_messages(user).count(title)).to eq(1)
end

Then('{string} should not get any alert containing {string}') do |name, text|
  user = evergreen_person(name)
  expect(evergreen_mails_to(user).map(&:subject).grep(/#{Regexp.escape(text)}/)).to be_empty
  expect(evergreen_inapp_messages(user).grep(/#{Regexp.escape(text)}/)).to be_empty
end

Then('nobody should get an alert containing {string}') do |text|
  expect(ActionMailer::Base.deliveries.map(&:subject).grep(/#{Regexp.escape(text)}/)).to be_empty
  messages = Noticed::Notification.where(type: "EvergreenOpsNotifier::Notification").map(&:message)
  expect(messages.grep(/#{Regexp.escape(text)}/)).to be_empty
end

Then('the alert {string} to {string} should list {string}') do |text, name, line|
  user = evergreen_person(name)
  mail = evergreen_mails_to(user).rfind { |m| m.subject == evergreen_alert_title(text) }
  expect(mail).to be_present
  expect(evergreen_mail_body(mail)).to include(line)
end

Then('the alert {string} to {string} should link to the dealing date {string}') do |text, name, date|
  user = evergreen_person(name)
  mail = evergreen_mails_to(user).rfind { |m| m.subject == evergreen_alert_title(text) }
  expect(mail).to be_present
  expect(evergreen_mail_body(mail)).to include(Rails.application.routes.url_helpers.evergreen_dealing_date_path(@fund, evergreen_dealing_date(date)))
end

Then('there should be {int} {string} notification log(s) for the order of {string}') do |count, key, name|
  order = evergreen_order_of(name)
  expect(EvergreenNotificationLog.where(key:, record_type: "DealingOrder", record_id: order.id).count).to eq(count)
end

# ---- Settings wizard: Notifications step ----

When('I open the notifications step of the evergreen settings') do
  evergreen_visit(evergreen_settings_path(@fund))
  # The switches are ios-toggle checkboxes (visually hidden input), so reveal the step by its number field
  evergreen_wizard_reveal("#notification_reminder_days")
end

Then('the notifications step should show every switch at its default with a tooltip and recipients') do
  catalogue = EvergreenFundSetting::NOTIFICATIONS
  # Design H54: five investor emails and nine team alerts. Counted from the catalogue so a later
  # alert (e.g. documents_awaiting_approval from the Approve & send change) only needs a catalogue row.
  expect(catalogue.count { |_, v| v[0] == :investor }).to eq(5)
  expect(catalogue.count { |_, v| v[0] == :internal }).to be >= 9
  %i[investor internal].each do |audience|
    expected = catalogue.count { |_, v| v[0] == audience }
    within("#notifications_#{audience}") do
      # Switches are ios-toggle checkboxes (the input itself may be visually hidden)
      expect(page).to have_css("input[type=checkbox][id^='notification_']", count: expected, visible: :all)
      expect(page).to have_css("[data-bs-title]", count: expected)
    end
  end
  catalogue.each do |key, (audience, default, label, recipients, description)|
    within("#notifications_#{audience}") do
      row = find("li", text: label)
      expect(row).to have_content(recipients)
      # Descriptions contain apostrophes, so compare the attribute rather than build a CSS selector
      expect(row.all("[data-bs-title]", visible: :all).pluck("data-bs-title")).to include(description)
    end
    default ? expect(page).to(have_checked_field("notification_#{key}", visible: :all)) : expect(page).to(have_unchecked_field("notification_#{key}", visible: :all))
  end
end

Then('the reminder days should show {string} and the large redemption threshold {string}') do |days, pct|
  expect(page).to have_field("notification_reminder_days", with: days)
  expect(page).to have_field("notification_large_redemption_pct", with: pct)
end

When('I set the reminder days to {string}') do |days|
  evergreen_wizard_reveal("#notification_reminder_days")
  fill_in("notification_reminder_days", with: days)
end

When('I set the large redemption threshold to {string}') do |pct|
  evergreen_wizard_reveal("#notification_large_redemption_pct")
  fill_in("notification_large_redemption_pct", with: pct)
end

Then('the fund reminder days should be {string}') do |days|
  expect(@fund.evergreen_fund_setting.reload.notification_number("reminder_days")).to eq(days.to_d)
end

Then('the fund large redemption threshold should be {string}') do |pct|
  expect(@fund.evergreen_fund_setting.reload.notification_number("large_redemption_pct")).to eq(pct.to_d)
end

Then('every notification switch of the fund should be at its default') do
  setting = @fund.evergreen_fund_setting.reload
  EvergreenFundSetting::NOTIFICATIONS.each do |key, (_, default)|
    expect(setting.notify?(key)).to eq(default), "#{key} should be #{default}"
  end
end

Then('the fund notification {string} should still be {string}') do |key, state|
  expect(@fund.evergreen_fund_setting.reload.notify?(key)).to eq(state == "on")
end

# ---- Copy from fund ----

# Another evergreen fund of the same entity (leaves @fund pointing at the fund under test)
Given('there is another evergreen fund {string}') do |name|
  current = @fund
  steps %(Given there is a fund "name=#{name};currency=INR;unit_types=A" for the entity)
  make_fund_evergreen(@fund, @user)
  @fund = current
end

# Enabled Evergreen templates on another fund, with attachment settings and show-details set
Given('the evergreen fund {string} of the entity has evergreen notifications for {string}') do |name, keys|
  steps %(Given there is another evergreen fund "#{name}") unless Fund.exists?(entity_id: @fund.entity_id, name:)
  source = Fund.find_by!(entity_id: @fund.entity_id, name:)
  keys.split(",").map(&:strip).each do |key|
    CustomNotification.create!(entity_id: source.entity_id, owner: source, for_type: "Evergreen", email_method: key, enabled: true,
                               subject: "#{name}: #{key.humanize}", body: "<p>#{name} wording for #{key.humanize}.</p>",
                               attachment_names: "Statement", attachment_mandatory: true, latest_doc_only: false,
                               show_details: true, show_details_link: false)
  end
end

When('I open Copy from fund for the fund') do
  @custom_notifications_before = CustomNotification.where(owner: @fund).count
  evergreen_visit(new_evergreen_notification_copy_path(@fund))
end

When('I copy the notifications from {string}') do |name|
  select(name, from: "from_fund_id")
  click_on("copy_notifications")
  # Copy templates asks first (Immediate Actions popup) — in a browser only; rack_test submits straight away
  within("#confirmModal") { click_on("Proceed") } unless Capybara.current_driver == :rack_test
end

Then('the fund should have the evergreen notifications of {string} for {string}') do |name, keys|
  source = Fund.find_by!(entity_id: @fund.entity_id, name:)
  fields = %w[subject body attachment_names attachment_mandatory latest_doc_only show_details show_details_link enabled]
  keys.split(",").map(&:strip).each do |key|
    from = source.custom_notifications.find_by!(for_type: "Evergreen", email_method: key)
    copy = @fund.custom_notifications.where(for_type: "Evergreen", email_method: key)
    expect(copy.count).to eq(1), "#{key}: #{copy.count} templates"
    expect(copy.first.attributes.slice(*fields)).to eq(from.attributes.slice(*fields))
  end
end

Then('the evergreen notification {string} of the fund should have subject {string}') do |key, subject|
  copies = @fund.custom_notifications.where(for_type: "Evergreen", email_method: key)
  expect(copies.pluck(:subject)).to eq([subject])
end

Then('the fund should have no evergreen notifications') do
  expect(@fund.custom_notifications.where(for_type: "Evergreen").count).to eq(0)
end

# X24: direct requests by users who cannot update the fund
When('{string} tries to copy the notifications from {string} to the fund') do |name, source_name|
  source = Fund.find_by!(entity_id: @fund.entity_id, name: source_name)
  session = evergreen_http_session(evergreen_person(name))
  session.post evergreen_notification_copy_path(@fund), params: { from_fund_id: source.id }
  # Refused by policy, not bounced to the login page
  expect(session.response.location.to_s).not_to include("sign_in")
  expect(session.response.location.to_s).not_to include("evergreen-notifications-tab")
end

When('{string} tries to switch the fund notification {string} off') do |name, key|
  session = evergreen_http_session(evergreen_person(name))
  session.patch evergreen_settings_path(@fund), params: { evergreen_fund_setting: { notifications: { key => "0" } } }
  expect(session.response.location.to_s).not_to include("sign_in")
end

# ---- Regression (E64) ----

Then('no evergreen notification should have been sent') do
  expect(EvergreenNotificationLog.count).to eq(0)
  expect(Noticed::Event.where(type: %w[EvergreenNotifier EvergreenOpsNotifier]).count).to eq(0)
end

Then('the user should still be tagged {string}') do |tags|
  expect(@user.reload.tag_list.to_s.split(",").map(&:strip)).to eq(tags.split(",").map(&:strip))
  expect(User::NOTIFICATION_TAGS).to include("Kpi", "Tasks", "db_dump_notification")
end
