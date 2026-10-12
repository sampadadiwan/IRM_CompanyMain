# Steps for features/fund/evergreen/gp_screens.feature.
# Worked examples H31–H35, E38, E45, E46 — openspec/changes/open-ended-funds/design.md#worked-examples

Then('I should see the evergreen tabs') do
  # Same structure as a closed-ended fund page: stats on top, details card, then the tab pills
  expect(page).to have_css("#evergreen_stats", text: "NAV")
  expect(page).to have_css("#evergreen_details_card", visible: :all) # inside the collapsed fund card
  within("#evergreen_tabs") do
    %w[Dealing NAV Investors Documents Access].each { |t| expect(page).to have_link(t) }
    %w[Subscriptions Redemptions Fees].each { |t| expect(page).to have_no_link(t, exact: false) }
  end
  # Grouped tabs: the orders sit inside Dealing, the fees inside NAV (counts are the open orders)
  within("#evergreen_dealing_tabs", visible: :all) do
    ["Dealing Dates", "Subscriptions (", "Redemptions ("].each { |t| expect(page).to have_css("a", text: t, visible: :all) }
  end
  within("#evergreen_nav_tabs", visible: :all) { expect(page).to have_css("a", text: "Fees", visible: :all) }
  expect(page).not_to have_css("#evergreen_tabs", text: "Commitments")
  expect(page).not_to have_css("#evergreen_tabs", text: "Calls")
end

When('I open the funds list as cards') do
  evergreen_visit(funds_path(card: :card))
end

Then('the card of {string} should show {string}') do |name, text|
  fund = Fund.find_by!(name:)
  expect(find("#fund_card_#{fund.id}")).to have_content(text)
end

# A settled fill dated in the quarter, for net flows (allotted / cancelled units)
Given('a settled {string} of {string} on dealing date {string}') do |kind, amount, date|
  d = Date.parse(date)
  dd = DealingDate.find_by(fund: @fund, date: d) || DealingDate.create!(entity_id: @fund.entity_id, fund: @fund, date: d, cutoff_at: d - 5.days,
                                                                        payment_timing: "before", status: "confirmed", confirmed_at: Time.current)
  cc = @fund.capital_commitments.first
  order = DealingOrder.create!(entity_id: @fund.entity_id, fund: @fund, investor: cc.investor, capital_commitment: cc, dealing_date: dd,
                               unit_type: cc.unit_type, kind:, status: "dealt", amount_cents: evergreen_cents(amount), received_at: d - 10.days)
  unit = FundUnit.create!(entity_id: @fund.entity_id, fund: @fund, capital_commitment: cc, investor: cc.investor, unit_type: cc.unit_type,
                          quantity: kind == "subscription" ? 1 : -1, price_cents: 100, premium_cents: 0, issue_date: d, reason: "settled")
  DealingFill.create!(entity_id: @fund.entity_id, fund: @fund, dealing_date: dd, dealing_order: order, kind:, unit_type: cc.unit_type,
                      units: 1, amount_cents: evergreen_cents(amount), nav_per_unit_cents: 100, fund_unit: unit)
end

# The overview figures now sit in the fund page's stats row (old overview links redirect there)
When('I open the evergreen overview') do
  evergreen_visit(evergreen_overview_path(@fund))
  expect(page).to have_css("#evergreen_stats")
end

When('I open the unit register') do
  evergreen_visit(evergreen_investors_path(@fund))
end

When('I open the fees tab') do
  evergreen_visit(evergreen_fees_path(@fund))
end

Then('the order of {string} should be highlighted as awaiting money') do |name|
  order = evergreen_order_of(name, "subscription")
  row = find("#order_#{order.id}")
  # Flagged by a "Cut-off <date>" badge next to Awaiting money (no row tint)
  expect(row).to have_css("#near_cutoff_#{order.id}")
  expect(row).to have_content("Awaiting money")
end

# ---- Folio page: Requests and Unit History tabs (H67, H68, E206, E207) ----
When('I open folio {string}') do |folio_id|
  @folio = @fund.capital_commitments.find_by!(folio_id:)
  evergreen_visit(evergreen_folio_path(@fund, @folio))
end

# The folio's latest order of a kind, by its row in the Requests table
Then('the folio request of the {string} should show {string}') do |kind, text|
  order = DealingOrder.where(capital_commitment_id: @folio.id, kind:).order(:id).last
  expect(find("#folio_order_#{order.id}", visible: :all).text(:all).squish).to include(text)
end

Then('the folio unit history row {int} should show {string} and balance {string}') do |n, text, balance|
  row = all("#folio_unit_history tbody tr", visible: :all)[n - 1]
  cells = row.all("td", visible: :all).map { |c| c.text(:all).squish }
  expect(cells.join(" | ")).to include(text)
  expect(cells.last).to eq(balance)
end

Then('the subscription row of the unit history should link to its order') do
  order = DealingOrder.where(capital_commitment_id: @folio.id, kind: "subscription").order(:id).last
  expect(page).to have_css("#folio_unit_history a[href='#{evergreen_order_path(@fund, order)}']", visible: :all)
end

# Grouped fund-page tabs: Dealing holds Dealing Dates / Subscriptions / Redemptions, NAV holds NAV / Fees (H31, E219, E220)
EVERGREEN_TAB_GROUPS = { "Dealing" => "#evergreen_dealing_tabs", "NAV" => "#evergreen_nav_tabs" }.freeze

When('I open the fund page on the tab {string}') do |tab|
  evergreen_visit(fund_path(@fund, tab:))
end

Then('the fund tab {string} should hold {string}') do |group, label|
  expect(page).to have_css("#{EVERGREEN_TAB_GROUPS.fetch(group)} a", text: label, visible: :all)
end

Then('the fund tab {string} should be active') do |label|
  expect(page).to have_css("#evergreen_tabs .nav-link.active", text: label)
end

Then('the inner fund tab {string} should be active') do |label|
  # The inner pill is switched on and its pane is the one shown
  expect(page).to have_css("#{EVERGREEN_TAB_GROUPS.values.join(' .nav-link.active, ')} .nav-link.active", text: label)
  expect(page).to have_css("#evergreen-#{label.downcase}-tab.show.active", visible: :all)
end

# ---- Fees tab rows (H104, E318–E321) ----
def evergreen_fees_row(unit_type, date)
  nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  find("#mgmt_fee_row_#{nav.id}")
end

Then('the fees row for class {string} on {string} should show {string}, {string}, {string} and {string}') do |unit_type, date, opening, accrued, paid, payable|
  # Cells 3–6: previous payable, + accrued, − paid, = payable
  cells = evergreen_fees_row(unit_type, date).all("td").map { |c| c.text.squish }
  expect(cells[2..5]).to eq([opening, accrued, paid, payable].map { |v| "₹#{v}" })
end

Then('the fees row for class {string} on {string} should show {string}') do |unit_type, date, text|
  expect(evergreen_fees_row(unit_type, date)).to have_content(text)
end

Then('the fees row for class {string} on {string} should offer Reopen') do |unit_type, date|
  nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  expect(evergreen_fees_row(unit_type, date)).to have_css("#reopen_nav_#{nav.id}")
end

Then('the fees row for class {string} on {string} should not offer Reopen') do |unit_type, date|
  expect(evergreen_fees_row(unit_type, date)).to have_no_css("[id^='reopen_nav_']")
end

Given('the class {string} NAV for {string} priced a dealing date on {string}') do |unit_type, date, dealing|
  @fund_nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  step %(a confirmed dealing date on "#{dealing}" priced at that NAV)
end

# F8 (E325): a class's first computed NAV, at its initial price with nothing outstanding
Given('a computed approved NAV for class {string} on {string} with no units outstanding') do |unit_type, date|
  FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: Date.parse(date), status: "approved", source: "computed",
                  units_outstanding: 0, nav_per_unit_cents: 1_000_000, nav_cents: 0, approved_at: Time.current)
end

# F10 (E327): the Net flows QTD card's figure and its tooltip working
Then('the net flows card should show an outflow of {string} with {string}') do |amount, tip|
  card = find("#evergreen_stats .card", text: "Net flows QTD")
  # Negative: the amount with a minus sign, wherever the currency formatter puts it
  expect(card.find("h2").text).to match(/-.*#{Regexp.escape(amount)}/)
  expect(card.find("[data-bs-toggle='tooltip']", visible: :all)["data-bs-title"]).to include(tip)
end
