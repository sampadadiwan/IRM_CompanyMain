# Steps for features/fund/evergreen/settlement.feature and documents.feature.
# Worked examples H22–H25, H36, E2, E31, E32, E51 — openspec/changes/open-ended-funds/design.md#worked-examples

def evergreen_fill_of(name, date)
  evergreen_dealing_date(date).dealing_fills.joins(dealing_order: :investor).find_by!(investors: { investor_name: name })
end

# A confirmed dealing date shows its fills in Subscriptions / Redemptions tabs, so a row in the other tab
# is hidden in a browser: open the fill's tab first (rack_test ignores visibility, so it never clicks)
def evergreen_show_fill_tab(fill)
  tab = fill.redemption? ? "#dealing_tab_redemptions" : "#dealing_tab_subscriptions"
  return if page.has_css?("#fill_#{fill.id}", wait: 0) || !page.has_css?(tab, wait: 0)

  find(tab).click
  expect(page).to have_css("#fill_#{fill.id}")
end

# Record payment / Mark paid ask for the date and reference in a small modal: open it in a browser
# (rack_test has no JS, so its fields are reachable without opening it)
def evergreen_open_fill_modal(action, fill)
  return if Capybara.current_driver == :rack_test

  find("##{action}_open_#{fill.id}").click
  expect(page).to have_css("##{action}_modal_#{fill.id}.show")
end

When('I record the payment of {string} on {string} in the tracker of {string}') do |name, paid_on, date|
  fill = evergreen_fill_of(name, date)
  evergreen_visit(evergreen_dealing_date_path(@fund, fill.dealing_date))
  evergreen_show_fill_tab(fill)
  evergreen_open_fill_modal("record_payment", fill)
  find("#payment_date_#{fill.id}").set(paid_on)
  click_on("record_payment_#{fill.id}")
  expect(page).to have_content("Payment recorded")
end

When('I mark the redemption of {string} paid on {string} with reference {string} in the tracker of {string}') do |name, paid_on, ref, date|
  fill = evergreen_fill_of(name, date)
  evergreen_visit(evergreen_dealing_date_path(@fund, fill.dealing_date))
  evergreen_show_fill_tab(fill)
  evergreen_open_fill_modal("mark_paid", fill)
  find("#paid_date_#{fill.id}").set(paid_on)
  fill_in("paid_reference_#{fill.id}", with: ref)
  click_on("mark_paid_#{fill.id}")
  expect(page).to have_content("Redemption marked paid")
end

Then('folio {string} should hold {string} units') do |folio, units|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  expect(FundUnit.where(capital_commitment_id: cc.id).sum(:quantity).to_d.round(4)).to eq(units.delete(",").to_d)
end

Then('the units of {string} on {string} should be {string} dated {string}') do |name, date, units, issued|
  fill = evergreen_fill_of(name, date)
  expect(fill.fund_unit).to be_present
  expect(fill.fund_unit.quantity.to_d.round(4)).to eq(units.delete(",").to_d)
  expect(fill.fund_unit.issue_date).to eq(Date.parse(issued))
end

Then('the {string} of {string} on {string} should show:') do |kind, name, date, table|
  fill = evergreen_fill_of(name, date)
  rows = EvergreenDocumentGenerator.new(fill, kind.parameterize(separator: "_").to_sym).rows.to_h
  table.rows_hash.each { |label, value| expect(rows[label]).to eq(value), "#{label}: #{rows[label]}" }
  # Without a template the investor is emailed straight away and no document is generated
  expect(fill.document_sent_at).to be_present
  expect(fill.document).to be_nil unless EvergreenDealingDocuments.template_for(fill)
end

Then('the redemption payment of {string} on {string} should have net payable {string}') do |name, date, amount|
  payment = evergreen_fill_of(name, date).capital_distribution_payment.reload
  expect((payment.net_payable_cents.to_d / 100).round(2)).to eq(amount.delete(",").to_d)
end

Then('folio {string} should have subscribed {string}') do |folio, amount|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  expect((cc.reload.committed_amount_cents.to_d / 100).round(2)).to eq(amount.delete(",").to_d)
end

Given('I note the subscribed amount of folio {string}') do |folio|
  # The folio's own subscribed amount (committed_amount_cents is only recomputed by later callbacks)
  @noted_committed = @fund.capital_commitments.find_by!(folio_id: folio).folio_committed_amount_cents.to_d
end

Then('folio {string} should have subscribed {string} more') do |folio, amount|
  cc = @fund.capital_commitments.find_by!(folio_id: folio).reload
  expect(((cc.folio_committed_amount_cents.to_d - @noted_committed) / 100).round(2)).to eq(amount.delete(",").to_d)
end

When('I follow the redemption settlement record of {string}') do |date|
  evergreen_visit(evergreen_dealing_date_path(@fund, evergreen_dealing_date(date)))
  within("#settlement_records") { click_on(EvergreenLabels.t(:distribution)) }
end

When('I open the old distribution page of {string}') do |date|
  evergreen_visit(capital_distribution_path(evergreen_dealing_date(date).redemption_distribution))
end

Then('I should be on the evergreen redemption settlement of {string}') do |date|
  expect(page).to have_css("#settlement_title", text: "Redemption settlement — #{I18n.l(Date.parse(date), format: :abbr_month_day_year, locale: :en)}")
  expect(page).to have_content(EvergreenLabels.t(:distribution_payments))
  expect(page).to have_css("#back_to_dealing_date")
  expect(page).not_to have_content("Redeem Units")
end

# E2: a closed-ended call and distribution behave as before (model level)
Given('the closed-ended fund {string} has a call with unit price {string} and a paid remittance of {string}') do |name, price, amount|
  steps %(Given there is a fund "name=#{name};currency=INR;unit_types=A" for the entity)
  @closed_fund = @fund
  steps %(Given there is an existing investor "name=Beta LP")
  @closed_folio = CapitalCommitment.new(entity_id: @fund.entity_id, fund: @fund, investor: @investor, unit_type: "A", folio_id: "B-1",
                                        folio_committed_amount_cents: 100_000_000_00, orig_folio_committed_amount_cents: 100_000_000_00,
                                        folio_currency: "INR", fund_close: "First Close", commitment_date: Date.new(2026, 1, 1))
  @closed_folio.save!(validate: false)
  @closed_call = CapitalCall.create!(entity_id: @fund.entity_id, fund: @fund, name: "Call 1", call_basis: "Upload", call_date: Date.new(2026, 2, 1),
                                     due_date: Date.new(2026, 2, 1), percentage_called: 0, approved: true, generate_remittances: false,
                                     unit_prices: { "A" => { "price" => price.delete(","), "premium" => "0" } })
  rem = CapitalRemittance.new(entity_id: @fund.entity_id, fund: @fund, capital_call: @closed_call, capital_commitment: @closed_folio, investor: @investor,
                              folio_id: "B-1", folio_call_amount_cents: evergreen_cents(amount), call_amount_cents: evergreen_cents(amount))
  CapitalRemittanceCreate.call(capital_remittance: rem)
  @closed_remittance = rem.reload
  CapitalRemittancePaymentCreate.call(capital_remittance_payment: CapitalRemittancePayment.new(
    entity_id: rem.entity_id, fund_id: rem.fund_id, capital_remittance: rem, amount_cents: rem.call_amount_cents,
    folio_amount_cents: rem.folio_call_amount_cents, payment_date: Date.new(2026, 2, 1)
  ))
  CapitalRemittanceVerify.call(capital_remittance: rem.reload, current_user: @user) unless rem.reload.verified
end

Then('the closed-ended remittance has no units until Allocate units') do
  expect(@closed_remittance.reload.verified).to be(true)
  expect(FundUnit.where(capital_commitment_id: @closed_folio.id).count).to eq(0)
  expect(@closed_call.skip_journey?).to be(false)
  DefaultUnitAllocationEngine.new.allocate_call(@closed_call, "Call 1", @user.id)
  expect(FundUnit.where(capital_commitment_id: @closed_folio.id).sum(:quantity).to_d.round(4)).to eq((evergreen_cents("10,00,000") / evergreen_cents("10,000")).round(4))
end

Then('a closed-ended distribution payment redeems amount ÷ price only when Redeem units runs') do
  dist = CapitalDistribution.new(entity_id: @closed_fund.entity_id, fund: @closed_fund, title: "Dist 1", distribution_date: Date.new(2026, 3, 1),
                                 distribution_on: "Upload", generate_payments: false, approved: true, unit_prices: { "A" => "10000" })
  CapitalDistributionCreate.call(capital_distribution: dist)
  payment = CapitalDistributionPayment.new(entity_id: dist.entity_id, fund_id: dist.fund_id, capital_distribution: dist, capital_commitment: @closed_folio,
                                           investor_id: @closed_folio.investor_id, folio_id: "B-1", cost_of_investment_cents: 20_000_000,
                                           income_cents: 0, reinvestment_cents: 0, payment_date: Date.new(2026, 3, 1), completed: true)
  CapitalDistributionPaymentCreate.call(capital_distribution_payment: payment)
  expect(payment.reload.fund_units.count).to eq(0)
  expect(dist.skip_journey?).to be(false)
  DefaultUnitAllocationEngine.new.allocate_distribution(dist, "Dist 1", @user.id)
  expect(payment.reload.fund_units.sum(:quantity).to_d).to eq(-20)
end

# Fund-level "Evergreen" custom notification (CustomNotification for_type "Evergreen")
Given('the fund has an evergreen notification for {string} with subject {string} and body {string}') do |email_method, subject, body|
  CustomNotification.create!(entity_id: @fund.entity_id, owner: @fund, for_type: "Evergreen", email_method:, enabled: true,
                             subject:, body: "<p>#{body}</p>")
end
