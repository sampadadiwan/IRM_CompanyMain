# frozen_string_literal: true

# The shared setup of openspec/changes/lp-mobile-app/design.md#worked-examples — Arka Growth
# Fund I, Sharma Family Office's ₹5,00,00,000 commitment, Calls 1–3, Distribution 1, documents —
# and the steps of features/mobile/mobile_data.feature.
#
# Amounts are pinned with update_columns after creation: the scenarios are about what the phone
# API READS, and the website computes these columns elsewhere (counter caches, set_status).

module MobileDataWorld
  CRORE = 10_000_000

  def rupees_cents(rupees) = (rupees.to_d * 100).to_i

  def arka
    @arka ||= {}
  end

  def investor_named(name)
    Investor.find_by!(investor_name: name)
  end

  # A fund the investor can see: an access right for the investor on the fund
  def mobile_fund!(name, fund_manager:, investor:, currency: "INR")
    fund = Fund.find_by(name:) || FactoryBot.create(:fund, name:, entity: fund_manager, currency:, unit_types: "A")
    AccessRight.find_or_create_by!(entity: fund_manager, owner: fund, access_to_investor_id: investor.id) { |ar| ar.notify = false }
    fund
  end

  def mobile_commitment!(fund, investor, committed:, called: 0, collected: 0, distributed: 0, folio: "F#{SecureRandom.hex(3)}")
    cc = FactoryBot.create(:capital_commitment, fund:, entity: fund.entity, investor:, unit_type: "A",
                                                folio_id: folio, folio_currency: fund.currency,
                                                folio_committed_amount_cents: rupees_cents(committed))
    cc.update_columns(committed_amount_cents: rupees_cents(committed), call_amount_cents: rupees_cents(called),
                      collected_amount_cents: rupees_cents(collected), distribution_amount_cents: rupees_cents(distributed),
                      other_fee_cents: 0)
    cc
  end

  def mobile_call!(fund, cc, name:, amount:, collected:, due_date:, status:)
    call = FactoryBot.create(:capital_call, fund:, entity: fund.entity, name:, call_basis: "Upload",
                                            due_date:, call_date: due_date - 30.days)
    rem = FactoryBot.create(:capital_remittance, capital_call: call, fund:, entity: fund.entity,
                                                 investor: cc.investor, capital_commitment: cc, folio_id: cc.folio_id,
                                                 folio_committed_amount_cents: cc.committed_amount_cents,
                                                 committed_amount_cents: cc.committed_amount_cents)
    rem.update_columns(call_amount_cents: rupees_cents(amount), collected_amount_cents: rupees_cents(collected),
                       other_fee_cents: 0, status:, verified: status != "Pending",
                       payment_date: status == "Paid" ? due_date - 5.days : nil)
    rem
  end

  # A document attached to `owner` in a folder of the fund manager's entity
  def mobile_document!(owner, name:, entity:, generated: false, approved: true, folder: nil)
    folder ||= owner.document_folder
    # Uploaded by fund-manager staff, as GP documents are
    uploader = entity.employees.first || FactoryBot.create(:user, entity:)
    doc = FactoryBot.create(:document, name:, entity:, owner:, folder:, approved:, user: uploader)
    doc.update_columns(from_template_id: doc.id) if generated
    doc
  end
end
World(MobileDataWorld)

# ── Shared setup ─────────────────────────────────────────────────────────────

Given("Arka Growth Fund I is set up for Sharma Family Office") do
  fm = Entity.find_by!(name: "Arka Capital")
  investor = investor_named("Sharma Family Office")
  fund = mobile_fund!("Arka Growth Fund I", fund_manager: fm, investor:)
  cc = mobile_commitment!(fund, investor, committed: 5 * MobileDataWorld::CRORE, called: 2 * MobileDataWorld::CRORE,
                                          collected: 1.25 * MobileDataWorld::CRORE, distributed: 3_000_000, folio: "SFO-1")
  arka.merge!(fm:, fund:, cc:, investor:)
  arka[:call1] = mobile_call!(fund, cc, name: "Capital Call 1", amount: 7_500_000, collected: 7_500_000,
                                        due_date: Date.new(2026, 1, 10), status: "Paid")
  arka[:call2] = mobile_call!(fund, cc, name: "Capital Call 2", amount: 5_000_000, collected: 5_000_000,
                                        due_date: Date.new(2026, 6, 17), status: "Paid")
  arka[:call3] = mobile_call!(fund, cc, name: "Capital Call 3", amount: 7_500_000, collected: 0,
                                        due_date: Date.new(2026, 10, 30), status: "Pending")
  dist = FactoryBot.create(:capital_distribution, fund:, entity: fm, title: "Distribution 1",
                                                  distribution_date: Date.new(2026, 8, 15))
  # Saving a distribution creates its payments per folio (CapitalDistribution callbacks); reuse it
  payment = CapitalDistributionPayment.find_by(capital_distribution: dist, folio_id: cc.folio_id) ||
            FactoryBot.create(:capital_distribution_payment, fund:, entity: fm, capital_distribution: dist,
                                                             investor:, capital_commitment: cc, folio_id: cc.folio_id,
                                                             payment_date: Date.new(2026, 8, 15))
  payment.update_columns(capital_commitment_id: cc.id, investor_id: investor.id, payment_date: Date.new(2026, 8, 15))
  payment.update_columns(net_payable_cents: rupees_cents(3_000_000), gross_payable_cents: rupees_cents(3_000_000), completed: true)
  arka[:payment] = payment
  # Pinned last: creating calls and distributions re-runs the commitment's counter caches
  cc.update_columns(committed_amount_cents: rupees_cents(5 * MobileDataWorld::CRORE), call_amount_cents: rupees_cents(2 * MobileDataWorld::CRORE),
                    collected_amount_cents: rupees_cents(1.25 * MobileDataWorld::CRORE), distribution_amount_cents: rupees_cents(3_000_000),
                    other_fee_cents: 0)
end

Given("Call 3 has an approved call notice") do
  arka[:notice] = mobile_document!(arka[:call3], name: "Capital Call 3 Notice", entity: arka[:fm], generated: true, approved: true)
end

Given("Call 3 has a generated call notice that is not approved yet") do
  arka[:notice] = mobile_document!(arka[:call3], name: "Capital Call 3 Notice", entity: arka[:fm], generated: true, approved: false)
end

Given("Distribution 1 has an approved distribution notice") do
  arka[:dist_notice] = mobile_document!(arka[:payment], name: "Distribution 1 Notice", entity: arka[:fm], generated: true, approved: true)
end

Given("Distribution 1 has a generated distribution notice that is not approved yet") do
  arka[:dist_notice] = mobile_document!(arka[:payment], name: "Distribution 1 Notice", entity: arka[:fm], generated: true, approved: false)
end

Given("the commitment has a document {string}") do |name|
  arka[:docs] ||= {}
  arka[:docs][name] = mobile_document!(arka[:cc], name:, entity: arka[:fm])
end

Given("the commitment has {int} documents") do |count|
  count.times { |i| mobile_document!(arka[:cc], name: "Statement #{i + 1}", entity: arka[:fm]) }
end

# Fund-level documents (data rooms, fund reports) are browsed on the website, behind its NDA gate
Given("the fund has a data room document {string}") do |name|
  arka[:docs] ||= {}
  arka[:docs][name] = mobile_document!(arka[:fund], name:, entity: arka[:fm])
end

Given("the document {string} is waiting for {string} to sign through {string}") do |name, email, provider|
  doc = arka[:docs].fetch(name)
  arka[:fm].entity_setting.update_columns(esign_provider: provider)
  doc.update_columns(sent_for_esign: true, provider_doc_id: "DID#{doc.id}", esign_status: "requested")
  esign = ESignature.create!(entity: arka[:fm], document: doc, user: mobile_user(email), email:, position: 1,
                             signature_type: "Electronic")
  # ESignature#update_status blanks the status whenever the signature type is set
  esign.update_columns(status: "requested")
end

Given("Call 3 has been paid") do
  arka[:call3].update_columns(collected_amount_cents: arka[:call3].call_amount_cents, status: "Paid")
end

Given("a call {string} that was due yesterday is unpaid") do |name|
  arka[:overdue] = mobile_call!(arka[:fund], arka[:cc], name:, amount: 1_000_000, collected: 0,
                                                        due_date: Time.zone.yesterday, status: "Overdue")
end

Given("Sharma Family Office has a second commitment to Arka Growth Fund I of {int}") do |rupees|
  mobile_commitment!(arka[:fund], arka[:investor], committed: rupees, folio: "SFO-2")
end

Given("Sharma Family Office has a commitment of {int} to {string} managed by {string}") do |rupees, fund_name, fm_name|
  fm = mobile_fund_manager(fm_name)
  investor = mobile_investor("Sharma Family Office", fm)
  FactoryBot.create(:investor_access, entity: fm, investor:, user: mobile_user("rahul@sharmafo.in"),
                                      email: "rahul@sharmafo.in", approved: true)
  fund = mobile_fund!(fund_name, fund_manager: fm, investor:)
  mobile_commitment!(fund, investor, committed: rupees)
end

Given("Kapoor Holdings has a capital call in Arka Growth Fund I") do
  kapoor = mobile_investor("Kapoor Holdings", arka[:fm])
  AccessRight.find_or_create_by!(entity: arka[:fm], owner: arka[:fund], access_to_investor_id: kapoor.id) { |ar| ar.notify = false }
  kapoor_cc = mobile_commitment!(arka[:fund], kapoor, committed: 10_000_000)
  arka[:kapoor_call] = mobile_call!(arka[:fund], kapoor_cc, name: "Kapoor Call", amount: 1_000_000, collected: 0,
                                                            due_date: Date.new(2026, 10, 30), status: "Pending")
  arka[:kapoor_doc] = mobile_document!(kapoor_cc, name: "Kapoor Statement", entity: arka[:fm])
end

Given("{string} has an unread notification for Capital Call 3") do |email|
  user = mobile_user(email)
  event = CapitalRemittanceNotifier.create!(record: arka[:call3], params: { entity_id: arka[:fm].id, email_method: "notify_capital_remittance" })
  arka[:notification] = Noticed::Notification.create!(event:, recipient: user, type: "CapitalRemittanceNotifier::Notification")
end

Given("{string} has an unread notification for Distribution 1") do |email|
  user = mobile_user(email)
  event = CapitalDistributionPaymentNotifier.create!(record: arka[:payment], params: { entity_id: arka[:fm].id, email_method: "send_notification" })
  Noticed::Notification.create!(event:, recipient: user, type: "CapitalDistributionPaymentNotifier::Notification")
end

Given("{string} has received {int} notifications") do |email, count|
  count.times { step %("#{email}" has an unread notification for Capital Call 3) }
end

# ── Requests that need the setup's ids ───────────────────────────────────────

When("the phone {string} opens the Arka fund's calls") do |phone_name|
  mobile_request(phone_name, :get, "/capital_remittances.json?capital_commitment_id=#{arka[:cc].id}&all=true")
end

When("the phone {string} opens the Arka fund's distributions") do |phone_name|
  mobile_request(phone_name, :get, "/capital_distribution_payments.json?capital_commitment_id=#{arka[:cc].id}")
end

When("the phone {string} opens Distribution 1") do |phone_name|
  mobile_request(phone_name, :get, "/capital_distribution_payments/#{arka[:payment].id}.json")
end

When("the phone {string} opens the Arka commitment") do |phone_name|
  mobile_request(phone_name, :get, "/capital_commitments/#{arka[:cc].id}.json")
end

When("the phone {string} opens Capital Call 3") do |phone_name|
  mobile_request(phone_name, :get, "/capital_remittances/#{arka[:call3].id}.json")
end

When("the phone {string} opens Kapoor's capital call") do |phone_name|
  mobile_request(phone_name, :get, "/capital_remittances/#{arka[:kapoor_call].id}.json")
end

When("the phone {string} opens the document {string}") do |phone_name, name|
  doc = name == "Kapoor Statement" ? arka[:kapoor_doc] : arka[:docs].fetch(name)
  mobile_request(phone_name, :get, "/documents/#{doc.id}.json")
end

When("the phone {string} marks the Capital Call 3 notification read") do |phone_name|
  mobile_request(phone_name, :patch, "/notifications/#{arka[:notification].id}/mark_as_read.json?mark=read")
end

When("the phone {string} marks all notifications read as {string}") do |phone_name, email|
  mobile_request(phone_name, :get, "/notifications.json?mark_as_read=1&user_id=#{mobile_user(email).id}")
end

When("the phone {string} switches to the persona {string}") do |phone_name, investor_entity_name|
  advisor = InvestorAdvisor.joins(:entity).find_by!(entities: { name: investor_entity_name })
  mobile_request(phone_name, :post, "/investor_advisors/switch?id=#{advisor.id}")
end

# ── Assertions ───────────────────────────────────────────────────────────────

Then("the phone sees the Arka card with committed {string}, called {string}, due {string} and distributed {string}") do |committed, called, due, distributed|
  card = last_phone.json["cards"].find { |c| c["fund_name"] == "Arka Growth Fund I" && c["folio_id"] == "SFO-1" }
  expect(card).to be_present, "cards: #{last_phone.json['cards']}"
  expect(card.dig("committed", "amount")).to eq(committed)
  expect(card.dig("called", "amount")).to eq(called)
  expect(card.dig("due", "amount")).to eq(due)
  expect(card.dig("distributed", "amount")).to eq(distributed)
  expect(card.dig("committed", "currency")).to eq("INR")
end

Then("the phone's To do lists {string}") do |titles|
  expect(last_phone.json["todo"].pluck("title")).to eq(titles.split(", "))
end

Then("the phone's To do is empty") do
  expect(last_phone.json["todo"]).to eq([])
end

Then("the phone sees {int} fund card(s)") do |count|
  expect(last_phone.json["cards"].size).to eq(count)
end

Then("the phone sees fund cards from {string}") do |names|
  expect(last_phone.json["cards"].pluck("entity_name").uniq.sort).to eq(names.split(", ").sort)
end

Then("the phone sees the calls {string}") do |rows|
  got = last_phone.json.map { |r| "#{r['capital_call_name']} #{format('%.2f', r['call_amount'])} #{r['status']}" }
  expect(got).to match_array(rows.split("; "))
end

Then("the phone sees the capital call {string} with status {string}, due amount {string} and due date {string}") do |name, status, due, date|
  expect(last_phone.json).to include("capital_call_name" => name, "status" => status, "due_date" => date)
  expect(format("%.2f", last_phone.json["due_amount"])).to eq(due)
end

Then("the capital call's notice is the approved call notice") do
  expect(last_phone.json["notice_document_id"]).to eq(arka[:notice].id)
end

Then("the phone sees the distribution payment {string} in {string} with net payable {string}") do |title, currency, net|
  expect(last_phone.json).to include("capital_distribution_title" => title, "fund_currency" => currency, "completed" => true)
  expect(format("%.2f", last_phone.json["net_payable"])).to eq(net)
end

Then("the distribution's notice is the approved distribution notice") do
  expect(last_phone.json["notice_document_id"]).to eq(arka[:dist_notice].id)
end

Then("the distribution has no notice") do
  expect(last_phone.json).to have_key("notice_document_id")
  expect(last_phone.json["notice_document_id"]).to be_nil
end

Then("the capital call has no notice") do
  expect(last_phone.json).to have_key("notice_document_id")
  expect(last_phone.json["notice_document_id"]).to be_nil
end

Then("{string} is recorded as having viewed {string}") do |email, name|
  doc = arka[:docs].fetch(name)
  expect(ViewedBy.where(owner: doc, user: mobile_user(email))).to exist
end

Then("{string} has not viewed {string}") do |email, _name|
  expect(ViewedBy.where(owner: arka[:kapoor_doc], user: mobile_user(email))).not_to exist
end

Then("the phone's document list has {int} item(s) and next page {string}") do |count, next_page|
  expect(last_phone.json["items"].size).to eq(count)
  expect(last_phone.json["next_page"].to_s).to eq(next_page)
end

Then("the phone's document list does not include {string}") do |name|
  expect(last_phone.json["items"].pluck("name")).not_to include(name)
end

Then("the phone's document list includes {string}") do |name|
  expect(last_phone.json["items"].pluck("name")).to include(name)
end

Then("{string} has {int} unread notification(s)") do |email, count|
  expect(mobile_user(email).notifications.unread.count).to eq(count)
end

Then("the phone sees the distribution {string} of {string}") do |title, amount|
  row = last_phone.json.find { |r| r["capital_distribution_title"] == title }
  expect(row).to be_present, "got #{last_phone.json}"
  expect(format("%.2f", row["net_payable"])).to eq(amount)
end

# An investor advisor approved by Sharma Family Office for Arka Growth Fund I — set up the way
# features/step_definitions/access_rights.rb sets up a real advisor (advisor record, the
# investor's access right on the fund for the advisor user, and investor access)
Given("{string} is an investor advisor approved by Sharma Family Office") do |email|
  advisor_entity = Entity.find_by(name: "Advisors LLP") ||
                   FactoryBot.create(:entity, name: "Advisors LLP", entity_type: "Investor Advisor")
  user = User.find_by(email:) || FactoryBot.create(:user, email:, entity: advisor_entity)
  investor = arka[:investor]
  advisor = InvestorAdvisor.create!(entity_id: investor.investor_entity_id, email: user.email)
  advisor.permissions.set(:enable_funds)
  advisor.save!
  AccessRight.create!(entity_id: investor.investor_entity_id, owner: arka[:fund], user_id: user.id,
                      metadata: "Investor Advisor", notify: false)
  InvestorAccess.create!(entity: arka[:fm], investor:, first_name: user.first_name, last_name: user.last_name,
                         email: user.email, approved: true)
  user.reload
end

# ── Website hand-off (features/mobile/mobile_web_handoff.feature) ────────────

When("the phone {string} asks for a website link to the Arka commitment page") do |phone_name|
  @handoff_path = "/capital_commitments/#{arka[:cc].id}"
  mobile_request(phone_name, :post, "/api/mobile/v1/web_handoffs", { path: @handoff_path })
  @handoff_url = last_phone.json["url"]
end

When("the phone {string} asks for a website link to Kapoor's capital call page") do |phone_name|
  @handoff_path = "/capital_remittances/#{arka[:kapoor_call].id}"
  mobile_request(phone_name, :post, "/api/mobile/v1/web_handoffs", { path: @handoff_path })
  @handoff_url = last_phone.json["url"]
end

When("I open the website link") do
  uri = URI.parse(@handoff_url)
  visit("#{uri.path}?#{uri.query}")
end

When("I sign out of the website") do
  Capybara.reset_session!
end

Then("I am on the Arka commitment page") do
  expect(page).to have_current_path(@handoff_path)
end

Then("I am on the website sign-in page") do
  expect(page).to have_current_path(new_user_session_path)
end

Given("Sharma Family Office holds a folio in the evergreen fund {string}") do |name|
  gp = arka[:fm].employees.first || FactoryBot.create(:user, entity: arka[:fm])
  fund = mobile_fund!(name, fund_manager: arka[:fm], investor: arka[:investor])
  make_fund_evergreen(fund, gp)
  mobile_commitment!(fund, arka[:investor], committed: 10_000_000, folio: "SFO-EG")
end

Given("Kapoor Holdings has its own investor advisor") do
  kapoor = mobile_investor("Kapoor Holdings", arka[:fm])
  other = FactoryBot.create(:user, entity: FactoryBot.create(:entity, entity_type: "Investor Advisor"))
  arka[:kapoor_advisor] = InvestorAdvisor.create!(entity_id: kapoor.investor_entity_id, email: other.email)
end

When("the phone {string} switches to Kapoor's advisor persona") do |phone_name|
  mobile_request(phone_name, :post, "/investor_advisors/switch?id=#{arka[:kapoor_advisor].id}")
end

Then("the phone sees an evergreen card for {string} with no NAV yet") do |name|
  card = last_phone.json["cards"].find { |c| c["fund_name"] == name }
  expect(card).to include("kind" => "evergreen", "value" => nil, "nav_per_unit" => nil)
  expect(card).not_to have_key("committed")
end

# ── Push (features/mobile/push_delivery.feature) ─────────────────────────────

Given("the phone {string} registered the push address {string}") do |phone_name, token|
  mobile_request(phone_name, :put, "/api/mobile/v1/device", { push_token: token })
  expect(last_phone.last_response.status).to eq(200)
end

Given("{string} switched off {string} push notifications") do |email, category|
  mobile_user(email).update_push_preferences!(category => false)
end

Given("Rahul's investor access to Arka Capital has email switched off") do
  InvestorAccess.where(entity: arka[:fm], user: mobile_user("rahul@sharmafo.in")).update_all(email_enabled: false)
end

Given("Arka Capital customised the capital call subject to {string}") do |subject|
  CustomNotification.create!(entity: arka[:fm], owner: arka[:call3].capital_call, email_method: "notify_capital_remittance",
                             subject:, body: "<div>Please pay by the due date.</div>", enabled: true)
end

Given("Expo will report {string} for the push address {string}") do |error, token|
  @expo.ticket_errors[token] = error
end

Given("Expo's receipt will report {string} for the push address {string}") do |error, token|
  @expo.receipt_errors[token] = error
end

Given("Expo is down") do
  @expo.status = 503
end

Given("push is not configured in this region") do
  allow(ExpoPushClient).to receive(:access_token).and_return(nil)
end

When("Arka Capital sends the Capital Call 3 notice to {string}") do |email|
  @notice_error = nil
  begin
    CapitalRemittanceNotifier.with(record: arka[:call3], entity_id: arka[:fm].id, email_method: :notify_capital_remittance)
                             .deliver(mobile_user(email))
  rescue ExpoPushClient::TransientError => e
    # X11 — inline jobs surface the push job's retryable error here; in production Noticed retries it
    @notice_error = e
  end
  @last_notification = Noticed::Notification.where(recipient: mobile_user(email)).order(:id).last
end

When("Arka Capital sends the Capital Call 3 notice to {string} with a {int}-character subject") do |email, length|
  step %(Arka Capital customised the capital call subject to "#{'A' * length}")
  step %(Arka Capital sends the Capital Call 3 notice to "#{email}")
end

When("the push job for that notification runs again") do
  DeliveryMethods::ExpoPush.new.perform(:push, @last_notification, overrides: {})
rescue ArgumentError
  DeliveryMethods::ExpoPush.new.perform(:push, @last_notification)
end

When("the push receipts are checked 16 minutes later") do
  travel(16.minutes) { ExpoPushReceiptsJob.perform_now }
end

Then("{int} push(es) was/were sent") do |count|
  expect(@expo.messages.size).to eq(count), "sent: #{@expo.messages}"
end

Then("the push address {string} got {int} push(es)") do |token, count|
  expect(@expo.to(token).size).to eq(count)
end

Then("each push is titled {string} and opens Capital Call 3") do |title|
  @expo.messages.each do |m|
    expect(m["title"]).to eq(title)
    expect(m.dig("data", "link")).to eq("/capital-calls/#{arka[:call3].id}")
  end
end

Then("the push body is {string}") do |body|
  expect(@expo.messages.last["body"]).to eq(body)
end

Then("the push body is {int} characters ending with {string}") do |length, ending|
  body = @expo.messages.last["body"]
  expect(body.length).to eq(length)
  expect(body).to end_with(ending)
end

Then("{string} still has the notification in their alerts") do |email|
  expect(Noticed::Notification.where(recipient: mobile_user(email))).to exist
end

Then("the phone {string} is marked {string} for push") do |phone_name, status|
  expect(MobileDevice.find_by!(install_id: phone(phone_name).install_id).push_status).to eq(status)
end

Then("the phone {string} has no push address") do |phone_name|
  expect(MobileDevice.find_by!(install_id: phone(phone_name).install_id).push_token).to be_nil
end

Then("the push job failed with a retryable error") do
  expect(@notice_error).to be_a(ExpoPushClient::TransientError)
end

Then("the email for the notification was sent to {string}") do |email|
  expect(ActionMailer::Base.deliveries.flat_map(&:to)).to include(email)
end

Given("Vikram's investor access to Arka Capital has email switched off") do
  InvestorAccess.where(entity: arka[:fm], user: mobile_user("vikram@kapoor.in")).update_all(email_enabled: false)
end

Then("a notification of type {string} is in the push category {string}") do |type, category|
  # A stand-in event: an unknown notifier class cannot be instantiated as a Noticed::Event (STI)
  event = Struct.new(:type, :record_type).new(type, nil)
  expect(MobilePushCategory.for(event)).to eq(category)
end

Given("{string} has a KYC request alert from Arka Capital") do |email|
  arka[:kyc] = FactoryBot.create(:investor_kyc, entity: arka[:fm], investor: arka[:investor])
  event = InvestorKycNotifier.create!(record: arka[:kyc], params: { entity_id: arka[:fm].id, email_method: "notify_kyc_required" })
  Noticed::Notification.create!(event:, recipient: mobile_user(email), type: "InvestorKycNotifier::Notification")
end

Then("the alert opens the website KYC form") do
  link = last_phone.json.first["link"]
  expect(link).to start_with("web:/investor_kycs/#{arka[:kyc].id}/edit")
  expect(Api::Mobile::V1::WebHandoffsController.safe_path?(link.delete_prefix("web:"))).to be(true)
end
