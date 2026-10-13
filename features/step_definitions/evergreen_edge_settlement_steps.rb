# Edge-case steps for settlement, payments, units and dealing-date documents:
# features/fund/evergreen/edge_settlement.feature and the edge scenarios of dealing_documents.feature.
# Worked examples E140–E150, X85–X94 (and X29) — openspec/changes/open-ended-funds/design.md#worked-examples
# Helpers reused from evergreen_settlement_steps.rb (evergreen_fill_of), evergreen_dealing_steps.rb
# (evergreen_dealing_date, evergreen_order_of) and evergreen_document_steps.rb (evergreen_doc_session, …).

# A team member (Asha, Ravi) by first name, or an investor's portal user by investor name
def evergreen_edge_user(name)
  # Investor portal users are keyed by investor name when the scenario created them
  return @investor_users[name] if @investor_users&.key?(name)

  evergreen_doc_user(name)
end

# "payment_date=2026-12-06;reference=X;amount=0" → { payment_date: "2026-12-06", … } ("" → {})
def evergreen_edge_params(values)
  values.to_s.split(";").each_with_object({}) do |kv, h|
    key, value = kv.split("=", 2)
    h[key.strip] = value.to_s.strip
  end
end

# ---- Direct requests (a hand-made POST, or a second click on a form that has already gone) ----

# Post a settlement-tracker row action (record_payment, verify, mark_paid, resend, regenerate) for a fill
When('{string} posts {string} for the fill of {string} on {string} directly with {string}') do |name, action, investor, date, values|
  fill = evergreen_fill_of(investor, date)
  # The route helpers are named <action>_evergreen_dealing_date_fill_path(fund, dealing_date, fill)
  path = public_send("#{action}_evergreen_dealing_date_fill_path", @fund, fill.dealing_date, fill)
  session = evergreen_doc_session(evergreen_edge_user(name))
  session.post path, params: evergreen_edge_params(values)
  # Keep where the request went and what the page said (shared with evergreen_document_steps.rb)
  evergreen_doc_follow(session)
end

# X94: Close dealing date posted directly (the screen shows it disabled)
When('{string} posts close for dealing date {string} directly') do |name, date|
  session = evergreen_doc_session(evergreen_edge_user(name))
  session.post close_evergreen_dealing_date_path(@fund, evergreen_dealing_date(date))
  evergreen_doc_follow(session)
end

# The action did not report success (whatever reason it gave) and the user is not sent to sign in
Then('the direct request should not say {string}') do |notice|
  expect(@direct_location).not_to include("sign_in")
  expect(CGI.unescapeHTML(@direct_body.to_s)).not_to include(notice)
end

# ---- Subscription payments and units ----

Then('the subscription payment of {string} should have {int} payment row(s)') do |name, count|
  rem = evergreen_order_of(name, "subscription").capital_remittance.reload
  expect(rem.capital_remittance_payments.count).to eq(count)
end

Then('the subscription payment of {string} should not be verified') do |name|
  expect(evergreen_order_of(name, "subscription").capital_remittance.reload.verified).to be(false)
end

Then('the subscription payment of {string} should have collected {string}') do |name, amount|
  rem = evergreen_order_of(name, "subscription").capital_remittance.reload
  expect((rem.collected_amount_cents.to_d / 100).round(2)).to eq(amount.delete(",").to_d)
end

Then('{string} on {string} should have no units') do |name, date|
  fill = evergreen_fill_of(name, date).reload
  expect(fill.fund_unit_id).to be_nil
  # …and nothing reached the folio through the remittance either
  expect(FundUnit.where(owner_type: "CapitalRemittance", owner_id: fill.capital_remittance_id).count).to eq(0) if fill.capital_remittance_id
end

# Exactly one unit row per fill: a retry or second click must not allot / cancel twice
Then('the folio of {string} on {string} should have exactly {int} unit row(s) from the dealing date') do |name, date, count|
  fill = evergreen_fill_of(name, date).reload
  folio = fill.dealing_order.capital_commitment
  expect(FundUnit.where(capital_commitment_id: folio.id).where("reason LIKE ?", "%dealing date #{Date.parse(date)}%").count).to eq(count)
end

# ---- Tracker rows ----

Then('the tracker row of {string} on {string} should not read {string}') do |name, date, text|
  fill = evergreen_fill_of(name, date)
  evergreen_show_fill_tab(fill)
  expect(find("#fill_#{fill.id}")).not_to have_content(text)
end

Then('the tracker row of {string} on {string} should show the part-paid badge') do |name, date|
  fill = evergreen_fill_of(name, date)
  evergreen_show_fill_tab(fill)
  expect(page).to have_css("#part_paid_#{fill.id}")
end

Then('the tracker row of {string} on {string} should not show the part-paid badge') do |name, date|
  fill = evergreen_fill_of(name, date)
  evergreen_show_fill_tab(fill)
  expect(page).to have_css("#fill_#{fill.id}")
  expect(page).not_to have_css("#part_paid_#{fill.id}")
end

# ---- Redemption payments ----

Then('the redemption of {string} on {string} should be paid on {string} with reference {string}') do |name, date, paid_on, ref|
  payment = evergreen_fill_of(name, date).capital_distribution_payment.reload
  expect(payment.completed).to be(true)
  expect(payment.payment_date).to eq(Date.parse(paid_on))
  # The bank reference lives in json_fields (CapitalDistributionPayment has no notes column)
  expect(payment.json_fields.to_h["payment_reference"]).to eq(ref)
end

Then('the redemption of {string} on {string} should not be paid') do |name, date|
  expect(evergreen_fill_of(name, date).capital_distribution_payment.reload.completed).to be(false)
end

# ---- Orders and folios ----

When('the fund admin cancels the order of {string}') do |name|
  result = DealingOrderCancel.call(order: evergreen_order_of(name), current_user: @gp_user || @user)
  raise "cancel failed: #{result[:errors]}" unless result.success?
end

Then('{string} should have folio {string}') do |name, folio|
  expect(evergreen_order_of(name).reload.capital_commitment&.folio_id).to eq(folio)
end

# ---- Documents ----

Then('the dealing date actions should not offer Generate documents') do
  expect(page).to have_css("#dealing_date_actions")
  within("#dealing_date_actions") { expect(page).not_to have_css("#generate_documents") }
end

# Note the generated-document count and start capturing job alerts afresh before an action
When('I note the generated documents') do
  @documents_before = Document.where(owner_tag: "Generated").count
  evergreen_capture_job_alerts
end

# One generated document per settled fill — never a duplicate from a second run
Then('there should be exactly {int} generated documents in the fund') do |count|
  folio_ids = @fund.capital_commitments.pluck(:id)
  expect(Document.where(owner_type: "CapitalCommitment", owner_id: folio_ids, owner_tag: "Generated").count).to eq(count)
end

# X95: the fund's template of one kind is deleted after an order has settled under it
When('the fund\'s {string} {string} is removed') do |tag, name|
  template = Document.find_by!(entity_id: @fund.entity_id, owner: @fund, name:, owner_tag: tag, template: true)
  template.destroy
  # The folio reads templates through the fund; make sure none is left for this kind
  expect(@fund.documents.templates.exists?(owner_tag: tag)).to be(false)
end

# X95: whatever the dealing date offers for an unsent document — the email may already have gone out
# automatically, or Generate documents is still offered and sends it — the investor must be emailed
When('the GP sends any outstanding documents of dealing date {string}') do |date|
  evergreen_visit(evergreen_dealing_date_path(@fund, evergreen_dealing_date(date)))
  # Only click when the screen offers it; the spec does not fix which path sends the email
  if page.has_css?("#generate_documents", wait: 2)
    click_on("generate_documents")
    # Generate / Send emails confirm first with the Immediate Actions popup (browser only — rack_test posts straight away)
    within("#confirmModal") { click_on("Proceed") } unless Capybara.current_driver == :rack_test
    # Wait for the request to finish before later steps read the mail deliveries
    expect(page).to have_content(/Emailed|Generating|Nothing to generate/)
  end
end
