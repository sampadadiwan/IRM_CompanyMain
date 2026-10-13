# Steps for features/fund/evergreen/class_nav.feature (and class_expenses.feature): how the shared NAV
# lines are split between classes by each class's stake.
# Worked examples H1–H6, E1–E24, X1–X6 — openspec/changes/evergreen-share-classes/design.md#worked-examples

# A previous approved NAV with any FundNav columns set — fee lines owed, crystallised, overrides.
# Money columns take rupees (with or without the _cents suffix); "crystallised" takes true/false;
# "overridden" names a line recorded as overridden (its column value is what the stake must use).
Given('an approved NAV for class {string} on {string} with NAV per unit {string}, units {string} and lines:') do |unit_type, date, per_unit, units, table|
  attrs = {}
  overrides = {}
  table.rows_hash.each do |key, value|
    case key
    when "crystallised" then attrs[:crystallised] = value == "true"
    when "overridden" then overrides[value] = { "value_cents" => "0", "reason" => "per admin statement" }
    else attrs[:"#{key.delete_suffix('_cents')}_cents"] = evergreen_cents(value)
    end
  end
  # Stored values first, then the override marker pointing at the line's stored (overridden) value
  overrides.each_key { |line| overrides[line]["value_cents"] = attrs[:"#{line}_cents"].to_s }
  FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: Date.parse(date), status: "approved",
                  source: overrides.any? ? "computed" : "uploaded", units_outstanding: units.delete(",").to_d,
                  nav_per_unit_cents: evergreen_cents(per_unit), nav_cents: evergreen_cents(per_unit) * units.delete(",").to_d,
                  approved_at: Time.current, overrides: overrides.presence, **attrs)
end

# Units cancelled from a folio (a redemption already settled), so the class holds fewer units now
Given('folio {string} had {string} units cancelled on {string}') do |folio_id, units, date|
  cc = CapitalCommitment.find_by!(fund: @fund, folio_id:)
  FundUnit.create!(entity_id: @fund.entity_id, fund: @fund, capital_commitment: cc, investor: cc.investor, unit_type: cc.unit_type,
                   quantity: -units.delete(",").to_d, price_cents: 1_000_000, premium_cents: 0,
                   issue_date: Date.parse(date), reason: "Redemption")
end

# Units issued to a folio after the previous NAV (a subscription dealt since)
Given('folio {string} was issued {string} units on {string}') do |folio_id, units, date|
  cc = CapitalCommitment.find_by!(fund: @fund, folio_id:)
  FundUnit.create!(entity_id: @fund.entity_id, fund: @fund, capital_commitment: cc, investor: cc.investor, unit_type: cc.unit_type,
                   quantity: units.delete(",").to_d, price_cents: 1_000_000, premium_cents: 0,
                   issue_date: Date.parse(date), reason: "Subscription")
end

# E10: the class NAVs on a date add up to the pool exactly (to the paisa)
Then('the class NAVs for {string} should add up to {string}') do |date, total|
  sum = FundNav.where(fund: @fund, nav_date: Date.parse(date)).sum(:nav_cents).to_d
  expect(sum.round(0)).to eq(evergreen_cents(total).round(0)), "class NAVs add up to #{sum / 100}, expected #{total}"
end

# E9: an approved NAV is never re-split — its stored figures stay as they were
Then('the approved class {string} NAV for {string} should still be:') do |unit_type, date, table|
  nav = FundNav.approved.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  table.rows_hash.each do |field, expected|
    expect(nav.send(field).to_d.round(2)).to eq(evergreen_cents(expected).round(2)), "#{field}: got #{nav.send(field).to_d / 100}"
  end
end

# ---- Class-only expenses (class_expenses.feature) ----

# Names a class's own expense entries directly, as saved settings would (H4, H5, E14–E24)
Given('class {string} uses expense entries {string} and {string}') do |unit_type, expense, paid|
  @fund.evergreen_class_terms.find_by!(unit_type:).update_columns(class_expense_entry_name: expense, class_expense_paid_entry_name: paid)
end

# The settings wizard: open the class card's "Customise this class" panel and type both names
When('I set the expense entries of class {string} to {string} and {string}') do |unit_type, expense, paid|
  card = "#class_term_#{unit_type.parameterize}"
  evergreen_wizard_reveal(card)
  within(card) do
    click_on("Customise this class")
    find("input[name$='[class_expense_entry_name]']", visible: true).fill_in(with: expense)
    find("input[name$='[class_expense_paid_entry_name]']").fill_in(with: paid)
  end
end

# X4: a direct request bypasses the form's 125-character limit
When('class {string} expense entries are set to a {int}-character name directly') do |unit_type, length|
  setting = @fund.evergreen_fund_setting.reload
  term = setting.evergreen_class_terms.find_by!(unit_type:)
  @settings_saved = setting.update(evergreen_class_terms_attributes: [{ id: term.id, class_expense_entry_name: "C" * length,
                                                                        class_expense_paid_entry_name: "Class #{unit_type} Paid" }])
  @settings_errors = setting.errors.full_messages
end

Then('the settings should be refused with {string}') do |message|
  expect(@settings_saved).to be(false)
  expect(@settings_errors).to include(message)
end

Then('class {string} should use expense entries {string} and {string}') do |unit_type, expense, paid|
  term = @fund.evergreen_class_terms.find_by!(unit_type:)
  expect([term.class_expense_entry_name, term.class_expense_paid_entry_name]).to eq([expense, paid])
end

# X6: the draft is refused and nothing is saved
When('drafting the NAV for {string} is refused with {string}') do |date, message|
  result = FundNavBuilder.call(fund: @fund.reload, nav_date: Date.parse(date), current_user: @user)
  expect(result.success?).to be(false)
  expect(result[:errors]).to include(message)
  expect(FundNav.where(fund: @fund, nav_date: Date.parse(date))).to be_none
end

Then('the NAV page should not show the line {string}') do |line|
  expect(page).to have_css("#nav_lines")
  expect(page).to have_no_css("#nav_line_#{line}")
end
