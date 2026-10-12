# Steps for features/fund/evergreen/dealing.feature and gates.feature (and the settlement feature).
# Worked examples H16–H21, H26, E6, E21–E30, E33, E34, X17, X20 — openspec/changes/open-ended-funds/design.md#worked-examples

def evergreen_order_of(name, kind = nil)
  scope = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name })
  scope = scope.where(kind:) if kind
  scope.order(:id).last
end

def evergreen_dealing_date(date)
  DealingDate.for(@fund, Date.parse(date))
end

Given('a draft NAV for class {string} on {string} with NAV per unit {string} and units {string}') do |unit_type, date, per_unit, units|
  FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: Date.parse(date), status: "draft", source: "uploaded",
                  units_outstanding: units.delete(",").to_d, nav_per_unit_cents: evergreen_cents(per_unit),
                  nav_cents: evergreen_cents(per_unit) * units.delete(",").to_d)
end

# Record and verify the full payment for a pre-funded subscription (as the tracker's Record payment does)
Given('{string} has paid the subscription on {string}') do |name, date|
  order = evergreen_order_of(name, "subscription")
  rem = order.capital_remittance
  CapitalRemittancePaymentCreate.call(capital_remittance_payment: CapitalRemittancePayment.new(
    entity_id: rem.entity_id, fund_id: rem.fund_id, capital_remittance: rem, amount_cents: rem.call_amount_cents,
    folio_amount_cents: rem.folio_call_amount_cents, payment_date: Date.parse(date)
  ))
  CapitalRemittanceVerify.call(capital_remittance: rem.reload, current_user: @gp_user || @user) unless rem.reload.verified
end

When('the dealing dates are generated') do
  DealingDateGenerateJob.perform_now(@fund.id)
end

When('I open the dealing list') do
  evergreen_visit(evergreen_dealing_dates_path(@fund))
end

Then('the dealing list should show {string} with cut-off {string} at step {string}') do |date, cutoff, step|
  row = find("#dealing_date_#{Date.parse(date).iso8601}")
  expect(row).to have_content(I18n.l(Date.parse(cutoff)))
  # The step shows as a badge (icon instead of the ○ / ● marker)
  expect(row).to have_content(step.sub(/\A[○●✓] /, ""))
end

When('I open the dealing date {string}') do |date|
  evergreen_visit(evergreen_dealing_date_path(@fund, evergreen_dealing_date(date)))
end

When('I confirm the dealing date') do
  click_on("confirm_dealing")
  within("#confirmModal") { click_on("Proceed") }
end

Then('the confirm button should be disabled') do
  expect(page).to have_css("#confirm_dealing_disabled")
  expect(page).not_to have_css("#confirm_dealing")
end

Then('the dealing date {string} should be {string}') do |date, status|
  expect(evergreen_dealing_date(date).reload.status).to eq(status)
end

Then('the journey of dealing date {string} should be at {string}') do |date, step|
  dd = evergreen_dealing_date(date)
  results = WorkflowEvaluator.for(dd, cause: :progress)&.[](:results) || []
  current = results.find { |r| r[:status].to_s == "current" || r[:current] }
  name = current && (current[:step]&.name || current[:name])
  expect(name).to eq(step)
end

# Pricing (no UI): | investor | filled | carried | (amounts in rupees)
Then('the pricing of {string} should fill:') do |date, table|
  pricing = DealingPricer.preview(evergreen_dealing_date(date))
  table.hashes.each do |row|
    r = pricing.redemptions.find { |x| x.order.investor.investor_name == row["investor"] }
    expect(r).to be_present, "no redemption row for #{row['investor']}"
    expect((r.value_cents / 100).round(2)).to eq(row["filled"].delete(",").to_d), "#{row['investor']} filled #{(r.value_cents / 100).to_s('F')}"
    if row["carried"]
      carried = ((r.requested_value_cents - r.value_cents) / 100).round(2)
      expect(carried).to eq(row["carried"].delete(",").to_d), "#{row['investor']} carried #{carried.to_s('F')}"
    end
    expect(r.filled_units.round(4)).to eq(row["units"].delete(",").to_d) if row["units"]
  end
end

Then('the pricing of {string} should allot {string} units to {string}') do |date, units, name|
  pricing = DealingPricer.preview(evergreen_dealing_date(date))
  r = pricing.subscriptions.find { |x| x.order.investor.investor_name == name }
  expect(r.units.round(4)).to eq(units.delete(",").to_d)
end

Then('the pricing of {string} should list {string} as {string}') do |date, name, text|
  pricing = DealingPricer.preview(evergreen_dealing_date(date))
  row = pricing.unready.find { |x| x.order.investor.investor_name == name }
  expect("#{row.reason} — #{row.fate}").to eq(text)
end

Then('the fills of dealing date {string} should be:') do |date, table|
  dd = evergreen_dealing_date(date)
  table.hashes.each do |row|
    fill = dd.dealing_fills.joins(dealing_order: :investor).find_by!(investors: { investor_name: row["investor"] })
    expect(fill.units.round(4)).to eq(row["units"].delete(",").to_d) if row["units"]
    expect((fill.amount_cents / 100).round(2)).to eq(row["amount"].delete(",").to_d) if row["amount"]
  end
end

Then('the subscription settlement of {string} should have unit price {string} for class {string}') do |date, price, unit_type|
  call = evergreen_dealing_date(date).subscription_call
  expect(call.name).to eq("Subscription settlement — #{I18n.l(Date.parse(date), format: :abbr_month_day_year, locale: :en)}")
  expect(call.unit_prices[unit_type]["price"].to_d).to eq(price.delete(",").to_d)
  expect(call.send_call_notice_flag).to be(false)
end

Then('the redemption settlement of {string} should have {string} payments due {string}') do |date, count, due|
  dist = evergreen_dealing_date(date).redemption_distribution
  expect(dist.title).to eq("Redemption settlement — #{I18n.l(Date.parse(date), format: :abbr_month_day_year, locale: :en)}")
  expect(dist.capital_distribution_payments.count).to eq(count.to_i)
  expect(dist.capital_distribution_payments.pluck(:payment_date).uniq).to eq([Date.parse(due)])
end

Then('the dealing date {string} should have no redemption settlement') do |date|
  expect(evergreen_dealing_date(date).reload.redemption_distribution_id).to be_nil
end

Then('no capital call or distribution notice was sent') do
  subjects = ActionMailer::Base.deliveries.map(&:subject)
  expect(subjects.grep(/Capital Call|Distribution/i)).to be_empty
end

Then('the order of {string} should be {string} on dealing date {string}') do |name, status, date|
  order = evergreen_order_of(name)
  expect(order.status).to eq(status)
  expect(order.dealing_date.date).to eq(Date.parse(date))
end

Then('in the queue of {string} {string} should be ahead of {string}') do |date, first, second|
  dd = evergreen_dealing_date(date)
  ids = DealingOrder.where(dealing_date: dd, kind: "redemption", status: DealingOrder::OPEN_STATUSES).in_queue_order.joins(:investor).pluck("investors.investor_name")
  expect(ids.index(first)).to be < ids.index(second)
end

When('the fund admin confirms dealing date {string} with a stale preview') do |date|
  dd = evergreen_dealing_date(date)
  stale = DealingPricer.preview(dd).hash_key
  # Something changes between the preview and the confirm (another user cancels an order)
  DealingOrderCancel.call(order: DealingOrder.where(dealing_date: dd).order(:id).first, current_user: @gp_user || @user)
  @confirm_result = DealingConfirm.call(dealing_date: dd.reload, current_user: @gp_user || @user, preview_hash: stale)
end

When('the fund admin confirms dealing date {string}') do |date|
  dd = evergreen_dealing_date(date)
  @confirm_result = DealingConfirm.call(dealing_date: dd, current_user: @gp_user || @user, preview_hash: DealingPricer.preview(dd).hash_key)
  raise "confirm failed: #{@confirm_result[:errors]}" unless @confirm_result.success?
end

Then('the confirm should be refused with {string}') do |msg|
  expect(@confirm_result.success?).to be(false)
  expect(@confirm_result[:errors]).to eq(msg)
end

When('I undo the dealing date') do
  click_on("undo_dealing")
  # Undo confirms first with the Immediate Actions popup
  # (only in a browser — rack_test has no JS, the button posts straight away)
  within("#confirmModal") { click_on("Proceed") } unless Capybara.current_driver == :rack_test
end

When('the fund setting changes to {string}') do |settings|
  steps %(Given the fund setting has "#{settings}")
end

Then('the confirmed gate of {string} should be {string}%') do |date, pct|
  expect(evergreen_dealing_date(date).gate_snapshot["pct"].to_d).to eq(pct.to_d)
end

Then('{string} received a gate notice') do |name|
  user = @investor_users.fetch(name)
  open_email(user.email)
  expect(current_email.subject).to eq("#{@fund.name}: Redemption partly filled")
end

Then('the subscription payment of {string} should be in the settlement of {string}') do |name, date|
  order = evergreen_order_of(name, "subscription")
  expect(order.capital_remittance.capital_call_id).to eq(evergreen_dealing_date(date).subscription_call_id)
end

Then('{string} should have no folio in the fund') do |name|
  order = evergreen_order_of(name, "subscription")
  expect(order.reload.capital_commitment_id).to be_nil
end

Given('the order of {string} is verified and accepted') do |name|
  order = evergreen_order_of(name)
  order.update!(signatory_verified_at: Time.current, accepted_at: Time.current)
  order.journey_progress!
end

# Dealing date tabs: one per order type with its count (E208, E209)
Then('the dealing tab {string} should be active') do |label|
  expect(page).to have_css("#dealing_date_tabs .nav-link.active", text: label, visible: :all)
end

Then('the dealing tab {string} should not be active') do |label|
  expect(page).to have_css("#dealing_date_tabs .nav-link:not(.active)", text: label, visible: :all)
end

# Redemption gate cards on the dealing date (E196, E210)
Then('the gate card should show {string} with {string}') do |stat, subtitle|
  card = all("#gate_summary .card", visible: :all).find { |c| c.text(:all).include?(subtitle) }
  expect(card).not_to be_nil, "no gate card with #{subtitle.inspect}"
  expect(card.text(:all)).to include(stat)
end

Then('the gate cards should show {string}') do |text|
  expect(find("#gate_summary", visible: :all).text(:all)).to include(text)
end

# A priced redemption's row on the dealing date — the same cells as the Redemptions list (E221)
Then('the dealing redemption row of {string} should show {string}') do |name, text|
  order = evergreen_order_of(name, "redemption")
  expect(find("#pricing_order_#{order.id}", visible: :all).text(:all)).to include(text)
end

# Dealing list filter (E222): "With orders" by default, "All dates" for the whole generated calendar
When('I open the dealing list filtered to {string}') do |label|
  evergreen_visit(evergreen_dealing_dates_path(@fund, filter: { "With orders" => "active", "All dates" => "all" }.fetch(label)))
end

Then('the dealing list should show the next date still taking orders') do
  next_date = DealingDate.where(fund: @fund, status: "open").where(cutoff_at: Time.current..).order(:date).first
  expect(next_date).to be_present
  expect(page).to have_css("#dealing_date_#{next_date.date.iso8601}")
end

Then('the dealing list should not show {string}') do |date|
  expect(page).to have_no_css("#dealing_date_#{Date.parse(date).iso8601}")
end

# E322: a ready order whose class has no usable NAV is listed, greyed, with the reason Confirm is blocked
Then('the redemption of {string} should be waiting for a NAV with {string}') do |investor, reason|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, kind: "redemption", investors: { investor_name: investor }).order(:id).last
  row = find("#awaiting_nav_order_#{order.id}", visible: :all)
  expect(row.text(:all).squish).to include("Waiting for NAV")
  expect(row.text(:all).squish).to include(reason)
end

# F2 / F5 (E323, E324): one dealing list row's redemption count and its step
Then('the dealing list row of {string} should show {int} redemptions') do |date, count|
  # Cells: date, cut-off, subscriptions, subscribed amount, redemptions, step, actions
  expect(find("#dealing_date_#{Date.parse(date).iso8601}").all("td")[4].text.strip).to eq(count.to_s)
end

Then('the dealing list row of {string} should be at step {string}') do |date, step|
  expect(find("#dealing_date_#{Date.parse(date).iso8601}").all("td")[5]).to have_content(step)
end
