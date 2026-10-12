# Steps for features/fund/evergreen/partial_payments.feature (§ Accept received amount).
# Worked examples E72, E73, X31 — openspec/changes/open-ended-funds/design.md#worked-examples

# Record a part payment through the same service as the order page / tracker
Given('{string} has paid {string} of the subscription on {string}') do |name, amount, date|
  order = evergreen_order_of(name, "subscription")
  ok, error = EvergreenPayments.record_subscription_payment(order.capital_remittance, amount: amount.delete(","), payment_date: Date.parse(date),
                                                                                      reference: "PART", user: @gp_user || @user)
  raise "payment failed: #{error}" unless ok
end

When('I accept the amount received for the order of {string}') do |name|
  order = evergreen_order_of(name, "subscription")
  evergreen_visit(evergreen_order_path(@fund, order))
  click_on("accept_received_#{order.id}")
  within("#confirmModal") { click_on("Proceed") }
  expect(page).to have_content("Subscription reduced to the amount received")
end

Then('the order of {string} should be for {string} reduced from {string}') do |name, amount, original|
  order = evergreen_order_of(name, "subscription").reload
  expect((order.amount_cents.to_d / 100).round(2)).to eq(amount.delete(",").to_d)
  expect((order.original_amount_cents.to_d / 100).round(2)).to eq(original.delete(",").to_d)
  expect(order.amount_reduced_by).to be_present
  expect(order.audits.pluck(:comment).compact.join).to include("reduced to the amount received")
end

Then('the subscription payment of {string} should ask for {string}') do |name, amount|
  rem = evergreen_order_of(name, "subscription").capital_remittance.reload
  expect((rem.call_amount_cents.to_d / 100).round(2)).to eq(amount.delete(",").to_d)
end

Then('the order page of {string} should not offer to accept the amount received') do |name|
  order = evergreen_order_of(name, "subscription")
  evergreen_visit(evergreen_order_path(@fund, order))
  expect(page).not_to have_css("#accept_received_#{order.id}")
end

When('the fund admin accepts the amount received for {string} directly') do |name|
  @accept_result = EvergreenAcceptReceived.call(order: evergreen_order_of(name, "subscription"), current_user: @gp_user || @user)
end

Then('accepting is refused with {string}') do |message|
  expect(@accept_result.success?).to be(false)
  expect(@accept_result[:errors]).to eq(message)
end
