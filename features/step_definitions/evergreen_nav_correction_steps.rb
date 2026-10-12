# Steps for features/fund/evergreen/nav_corrections.feature — the two NAV corrections decided on
# 8 Oct 2026: fee payments settle the class that owed them, and money for orders not yet dealt is
# kept out of the NAV. Worked examples E197–E204 — openspec/changes/open-ended-funds/design.md#worked-examples

# A previous approved NAV carrying fee payables, so the next draft has something owed
Given('an approved NAV for class {string} on {string} with NAV per unit {string}, units {string} and payables:') do |unit_type, date, per_unit, units, table|
  # Keys may be written with or without the _cents suffix
  payables = table.rows_hash.to_h { |k, v| [k.delete_suffix("_cents"), evergreen_cents(v)] }
  FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: Date.parse(date), status: "approved", source: "uploaded",
                  units_outstanding: units.delete(",").to_d, nav_per_unit_cents: evergreen_cents(per_unit),
                  nav_cents: evergreen_cents(per_unit) * units.delete(",").to_d, approved_at: Time.current,
                  mgmt_fee_payable_cents: payables.fetch("mgmt_fee_payable", 0), perf_fee_payable_cents: payables.fetch("perf_fee_payable", 0))
end

# Draft through the same operation as the Draft button, failing loudly if it is refused
When('the NAV for {string} is drafted') do |date|
  result = FundNavBuilder.call(fund: @fund.reload, nav_date: Date.parse(date), current_user: @user)
  raise "draft failed: #{result[:errors]}" unless result.success?
end

# The orders listed behind the dealing-in-progress line (NAV breakdown)
Then('the class {string} NAV for {string} should list {string} as money for orders not yet dealt') do |unit_type, date, text|
  nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  expect(nav.breakdown.to_h["dealing_in_progress"].to_s).to include(text)
end
