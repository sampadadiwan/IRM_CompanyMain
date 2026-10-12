# Edge-case steps for features/fund/evergreen/orders.feature, order_journeys.feature and
# partial_payments.feature: refusals captured instead of raised, lock-up fee checks, past redemptions,
# direct cancels and accept-received attempts.
# Worked examples E80–E97, X40–X54 — openspec/changes/open-ended-funds/design.md#worked-examples

# Place an order through DealingOrderCreate (as an admin) and keep the result, so refusals can be asserted.
# Values: folio=F-012 (any folio of the fund, even another investor's), class=B, units/amount/all_units.
When('{string} tries a {string} order {string} received {string}') do |name, kind, values, received|
  # The investor placing the order
  inv = Investor.find_by!(entity_id: @fund.entity_id, investor_name: name)
  kv = evergreen_kv(values)
  # Folio looked up by number in this fund only; an unknown number leaves the order folio-less
  folio = @fund.capital_commitments.find_by(folio_id: kv.delete(:folio)) if kv[:folio]
  unit_type = kv.delete(:class) || "A"
  params = kv.merge(kind:, investor_id: inv.id, capital_commitment_id: folio&.id, unit_type:, received_at: received)
  # Remember the count so "refused" can also check nothing was saved
  @orders_before = DealingOrder.count
  @order_result = DealingOrderCreate.call(fund: @fund, params:, current_user: @gp_user || @user, source: "admin")
end

Then('the order should be refused with {string}') do |message|
  expect(@order_result.success?).to be(false), "expected a refusal, but the order was created"
  expect(@order_result[:errors]).to eq(message)
  # A refused order leaves nothing behind
  expect(DealingOrder.count).to eq(@orders_before)
end

Then('the order should be refused') do
  expect(@order_result.success?).to be(false), "expected a refusal, but order #{@order_result[:order]&.id} was created " \
                                               "(units #{@order_result[:order]&.units&.to_s('F')})"
  expect(DealingOrder.count).to eq(@orders_before)
end

Then('the order should be accepted') do
  expect(@order_result.success?).to be(true), "refused with: #{@order_result[:errors]}"
end

# Soft lock-up: the fee % and the locked units recorded on the investor's latest order
Then('the order of {string} should record an early-redemption fee of {string}% on {string} units') do |name, pct, units|
  order = evergreen_order_of(name).reload
  expect(order.early_fee_pct.to_d).to eq(pct.to_d)
  expect(order.locked_units.to_d).to eq(units.delete(",").to_d)
end

Then('the order of {string} should have no early-redemption fee') do |name|
  order = evergreen_order_of(name).reload
  expect(order.early_fee_pct.to_d).to be_zero
  expect(order.locked_units.to_d).to be_zero
end

# A past, paid redemption: a negative FundUnit on the folio (as DealingSettlement writes when paid)
Given('{string} redeemed {string} units of class {string} from folio {string} on {string}') do |name, units, unit_type, folio, date|
  inv = Investor.find_by!(entity_id: @fund.entity_id, investor_name: name)
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  FundUnit.create!(entity_id: @fund.entity_id, fund: @fund, capital_commitment: cc, investor: inv, unit_type:,
                   quantity: -units.delete(",").to_d, price_cents: 1_000_000, premium_cents: 0, issue_date: Date.parse(date),
                   reason: "Redemption")
end

# The early-redemption fee the dealing date would deduct from the investor's redemption (rupees)
Then('the pricing of {string} should charge {string} an early-redemption fee of {string}') do |date, name, fee|
  pricing = DealingPricer.preview(evergreen_dealing_date(date))
  row = pricing.redemptions.find { |r| r.order.investor.investor_name == name }
  expect(row).to be_present, "no priced redemption for #{name} on #{date}"
  expect((row.early_fee_cents.to_d / 100).round(2)).to eq(fee.delete(",").to_d)
end

# Cancel through the same operation as the Cancel button, keeping the result
When('the order of {string} is cancelled directly') do |name|
  @cancel_result = DealingOrderCancel.call(order: evergreen_order_of(name).reload, current_user: @gp_user || @user)
end

Then('cancelling is refused with {string}') do |message|
  expect(@cancel_result.success?).to be(false)
  expect(@cancel_result[:errors]).to eq(message)
end

Then('cancelling succeeds') do
  expect(@cancel_result.success?).to be(true), "refused with: #{@cancel_result[:errors]}"
end

# "Accept received amount" posted for a redemption (the button is never shown on one)
When('the fund admin accepts the amount received for the redemption of {string} directly') do |name|
  @accept_result = EvergreenAcceptReceived.call(order: evergreen_order_of(name, "redemption"), current_user: @gp_user || @user)
end
