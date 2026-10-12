# Steps for features/fund/evergreen/investor_portal.feature.
# Worked examples H37, H38, H39, E12, E17, E48, E49, E50, X19 — openspec/changes/open-ended-funds/design.md#worked-examples

Given('{string} holds {string} units of class {string} in folio {string} issued {string} at {string}') do |name, units, unit_type, folio, issued, price|
  steps %(Given "#{name}" holds "0.0001" units of class "#{unit_type}" in folio "#{folio}" issued "#{issued}")
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  FundUnit.where(capital_commitment_id: cc.id).delete_all
  FundUnit.create!(entity_id: @fund.entity_id, fund: @fund, capital_commitment: cc, investor: cc.investor, unit_type:,
                   quantity: units.delete(",").to_d, price_cents: evergreen_cents(price), premium_cents: 0, issue_date: Date.parse(issued), reason: "Allotted")
end

When('I open the fund as an investor') do
  evergreen_visit(fund_path(@fund))
end

When('I open the investor tab {string}') do |tab|
  click_on("lp_tab_#{tab.parameterize}")
end

Then('I should not see closed-ended figures') do
  %w[Committed Uncalled Called].each { |w| expect(page).not_to have_css("#evergreen_investor_page", text: /\b#{w}\b/) }
end

Then('the statement of folio {string} for {string} to {string} should have:') do |folio, from, to, table|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  ctx = EvergreenStatement.new(cc, Date.parse(from), Date.parse(to)).context
  table.rows_hash.each { |k, v| expect(ctx[k].to_d.round(4)).to eq(v.delete(",").to_d), "#{k}: #{ctx[k]}" }
end

When('I open the order of {string} directly') do |name|
  evergreen_visit(evergreen_order_path(@fund, evergreen_order_of(name)))
end

Then('I should not see the order') do
  expect(page).not_to have_css("#order_card")
end

# Portal home (LP landing page) — the evergreen folio card. Worked examples E180, X115
When('I open the portal home') do
  evergreen_visit(root_path)
end

# The card for a folio of the current fund
def evergreen_portal_card(folio)
  find("#lp_card_#{@fund.capital_commitments.find_by!(folio_id: folio).id}")
end

Then('the portal card of folio {string} should show {string}') do |folio, text|
  expect(evergreen_portal_card(folio)).to have_content(text)
end

Then('the portal card of folio {string} should not show {string}') do |folio, text|
  expect(evergreen_portal_card(folio)).not_to have_content(text)
end

Then('the portal card of folio {string} should offer Redeem') do |folio|
  # An enabled Redeem is a link; a disabled one is a span
  expect(evergreen_portal_card(folio)).to have_css("a[id^='lp_card_redeem_']", text: "Redeem")
end

Then('the portal card of folio {string} should not offer Redeem') do |folio|
  card = evergreen_portal_card(folio)
  expect(card).not_to have_css("a[id^='lp_card_redeem_']")
  expect(card).to have_css("span.disabled[id^='lp_card_redeem_']", text: "Redeem")
end

# Each LP accordion section carries its own header, since the open section's button is hidden (E211)
Then('the portal section {string} should have the header {string}') do |key, title|
  expect(find("#lp_header_#{key}", visible: :all).text(:all)).to include(title)
end
