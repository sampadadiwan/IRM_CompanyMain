# Steps for features/fund/evergreen/review_fixes.feature — Decisions 3 and 4
# (docs/modules/funds/evergreen_design_decisions.md) and the review fixes of 10 Oct 2026.
# Worked examples H101–H103, E301–E317, X201–X203. Shared helpers come from the other evergreen step
# files (evergreen_dealing_date, evergreen_order_of, evergreen_fill_of, evergreen_person, …).

# ---- Dealing dates ----
# Confirm / undo without raising reuse evergreen_edge_dealing_steps.rb: "the fund admin tries to confirm
# dealing date", "the fund admin undoes dealing date", "the undo should succeed / be refused with".

# X202: make FolioOpener fail as it would when a folio can't be saved
Given('re-opening a folio fails with {string}') do |msg|
  allow(FolioOpener).to receive(:call).and_raise(FolioOpener::Error, msg)
end

Then('the order of {string} should have status {string}') do |name, status|
  expect(evergreen_order_of(name).reload.status).to eq(status)
end

# X203: closing needs every row settled; the scenario only needs the closed state
Given('the dealing date {string} is closed') do |date|
  evergreen_dealing_date(date).update_columns(status: "closed", closed_at: Time.current)
end

# E303 (ready to confirm): the alert's subject / in-app message contains the text
Then('{string} should get an alert containing {string}') do |name, text|
  user = evergreen_person(name)
  expect(evergreen_mails_to(user).map(&:subject).grep(/#{Regexp.escape(text)}/)).not_to be_empty
end

# ---- NAVs ----

When('I try to approve the class {string} NAV for {string} directly') do |unit_type, date|
  nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  @nav_result = FundNavApprove.call(fund_nav: nav, current_user: @user.reload)
end

Then('the approval should succeed') do
  expect(@nav_result.success?).to be(true), "approval refused: #{@nav_result[:errors]}"
end

When('{string} tries to draft the NAV for {string}') do |name, date|
  @draft_result = FundNavBuilder.call(fund: @fund.reload, nav_date: Date.parse(date), current_user: evergreen_person(name))
end

Then('drafting should be refused with {string}') do |msg|
  expect(@draft_result.success?).to be(false)
  expect(@draft_result[:errors]).to eq(msg)
end

# E308: neither the NAV-page / Fees-tab warning nor the Fund accounting alert applies to an uploaded NAV
Then('the class {string} NAV for {string} should show no fee accrual warning') do |unit_type, date|
  nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  expect(nav.uploaded?).to be(true)
  expect(ApplicationController.helpers.evergreen_mgmt_fee_warning(nav)).to be_nil
  expect(EvergreenAlerts.send(:fee_accrual_behind?, nav)).to be(false)
end

# ---- Settlement ----

# E309: money recorded on the remittance (as from the remittance screen), short by a few paise, not verified
Given('{string} has an unverified payment {string} short of the subscription on {string}') do |name, short, date|
  rem = evergreen_order_of(name, "subscription").reload.capital_remittance
  amount = rem.call_amount_cents.to_d - (short.to_d * 100)
  CapitalRemittancePaymentCreate.call(capital_remittance_payment: CapitalRemittancePayment.new(
    entity_id: rem.entity_id, fund_id: rem.fund_id, capital_remittance: rem, amount_cents: amount,
    folio_amount_cents: amount, payment_date: Date.parse(date)
  ))
  expect(rem.reload.verified).to be(false)
end

Then('the tracker row of {string} on {string} should offer {string} and not {string}') do |name, date, offered, absent|
  fill = evergreen_fill_of(name, date)
  evergreen_show_fill_tab(fill)
  within("#fill_#{fill.id}") do
    expect(page).to have_content(offered)
    expect(page).not_to have_content(absent)
  end
end

# ---- Email templates ----

# "subject=Got it;body=Thanks;show_details=true;show_details_link=true;whatsapp=…"
Given('the fund has an evergreen template for {string} with {string}') do |email_method, values|
  attrs = { subject: "Update", body: "Update" }.merge(evergreen_kv(values))
  %i[show_details show_details_link].each { |k| attrs[k] = attrs[k] == "true" if attrs.key?(k) }
  CustomNotification.create!(entity_id: @fund.entity_id, owner: @fund, for_type: "Evergreen", email_method:, enabled: true, **attrs)
end

# E310: the notifier answers custom_notification, which is what gates the WhatsApp delivery
Then('the evergreen notification for the order of {string} should carry WhatsApp text {string}') do |name, text|
  order = evergreen_order_of(name)
  notification = Noticed::Notification.where(type: "EvergreenNotifier::Notification").order(:id).last
  expect(notification.event.record).to eq(order)
  expect(notification.custom_notification&.whatsapp).to eq(text)
  expect(notification.custom_notification_whatsapp_present?).to be(true)
end

# E312: a template file on a folio (as the contract-note template steps create)
Given('folio {string} has a template document {string}') do |folio_id, name|
  folio = @fund.capital_commitments.find_by!(folio_id:)
  evergreen_doc_template(folio, name, "Contract Note Template", "Commitment Agreement Template.docx")
end

# ---- Queue ----

Then('the redemption of {string} should be {string} in its queue') do |name, place|
  expect("##{evergreen_order_of(name, 'redemption').reload.queue_position}").to eq(place)
end

Then('the queue tooltip of {string} should say {string}') do |name, text|
  order = evergreen_order_of(name, "redemption").reload
  expect(ApplicationController.helpers.eg_queue_tooltip(order, order.queue_position)).to include(text)
end

# ---- Gate ----

Then('the gate of dealing date {string} should have {string} used and {string} left') do |date, used, left|
  gate = DealingPricer.preview(evergreen_dealing_date(date)).gate
  expect(gate[:used]["fund"].to_d.round(2)).to eq(evergreen_cents(used).round(2))
  expect(gate[:pools]["fund"].to_d.round(2)).to eq(evergreen_cents(left).round(2))
end

# ---- Read-only user ----

# An employee who can only read this fund (fund access right without the update permission)
Given('there is an employee {string} who can only read the fund') do |name|
  user = FactoryBot.create(:user, entity: @fund.entity, first_name: name)
  user.add_role(:employee)
  user.update_columns(curr_role: "employee")
  AccessRight.create!(entity_id: @fund.entity_id, owner: @fund, user_id: user.id, access_type: "Fund", notify: false)
  expect(FundPolicy.new(user.reload, @fund).show?).to be(true)
  expect(FundPolicy.new(user, @fund).update?).to be(false)
end
