# Edge-case steps for NAV, fees and settings (nav.feature, fees.feature, settings.feature,
# edge_nav_fees.feature). Direct-request steps call the same operations the controllers call, so a
# refusal is proven at the server and not only by a hidden button.
# Worked examples E120–E139, X70–X84 — openspec/changes/open-ended-funds/design.md#worked-examples

# The user an actor phrase refers to: the approver created by "there is an approver" (or by the
# drafted-and-approved step), else the GP user who prepared the NAV
def evergreen_edge_actor(actor)
  case actor
  when "approver" then @approver || raise("No approver in this scenario")
  else @gp_user || @user
  end
end

def evergreen_edge_nav(unit_type, date)
  # Always re-read: earlier steps may have changed the row behind any cached instance
  FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
end

# ---- Direct requests (bypassing the hidden buttons) ----

When('the {word} tries to approve the class {string} NAV for {string} directly') do |actor, unit_type, date|
  @nav_result = FundNavApprove.call(fund_nav: evergreen_edge_nav(unit_type, date), current_user: evergreen_edge_actor(actor))
end

When('the {word} tries to reopen the class {string} NAV for {string} directly') do |actor, unit_type, date|
  @nav_result = FundNavReopen.call(fund_nav: evergreen_edge_nav(unit_type, date), current_user: evergreen_edge_actor(actor))
end

When('the {word} tries to override line {string} of the class {string} NAV for {string} to {string} with reason {string} directly') do |actor, line, unit_type, date, value, reason|
  @nav_result = FundNavOverride.call(fund_nav: evergreen_edge_nav(unit_type, date), line:, value:, reason:,
                                     current_user: evergreen_edge_actor(actor))
end

When('the {word} tries to override line {string} of the class {string} NAV for {string} to {string} with a reason of {int} characters directly') do |actor, line, unit_type, date, value, length|
  # The browser's maxlength=255 would truncate a longer reason, so the 256-character case is a direct request
  @nav_result = FundNavOverride.call(fund_nav: evergreen_edge_nav(unit_type, date), line:, value:, reason: "r" * length,
                                     current_user: evergreen_edge_actor(actor))
end

Then('the request is refused with {string}') do |msg|
  expect(@nav_result.success?).to be(false)
  expect(@nav_result[:errors]).to eq(msg)
end

# ---- NAV assertions ----

Then('there should be no class {string} NAV for {string}') do |unit_type, date|
  expect(FundNav.where(fund: @fund, unit_type:, nav_date: Date.parse(date))).not_to exist
end

Then('there should be {int} class {string} NAV(s) for {string}') do |count, unit_type, date|
  expect(FundNav.where(fund: @fund, unit_type:, nav_date: Date.parse(date)).count).to eq(count)
end

Then('the class {string} NAV for {string} should have no overrides') do |unit_type, date|
  expect(evergreen_edge_nav(unit_type, date).overrides_hash).to be_empty
end

Then('the class {string} NAV for {string} should have no high-water mark') do |unit_type, date|
  expect(evergreen_edge_nav(unit_type, date).hwm_cents).to be_nil
end

Then('the {string} override of the class {string} NAV for {string} should have a {int}-character reason') do |line, unit_type, date, length|
  expect(evergreen_edge_nav(unit_type, date).overrides_hash.dig(line, "reason").length).to eq(length)
end

Then('I should not be able to override the NAV') do
  # Page rendered first (NAV lines table), then the override card must be absent
  expect(page).to have_css("#nav_lines")
  expect(page).not_to have_css("#override_form")
end

Then('I should not be able to reopen the NAV') do
  expect(page).to have_css("#nav_lines")
  expect(page).not_to have_css("#reopen_nav")
end

When('I override the NAV line {string} to {string} with a reason of {int} characters') do |line, value, length|
  # Override line opens a small modal (browser runs only — rack_test reaches the fields directly)
  evergreen_open_nav_modal("override")
  select(line, from: "override_line")
  fill_in("override_value", with: value.delete(","))
  fill_in("override_reason", with: "r" * length)
  click_on("override_submit")
end

# ---- Management fee per class ----

Then('the class {string} management fee entries for {string} should total {string}') do |unit_type, date, total|
  # Folio entries of this class only (the run also writes a fund-level cumulative total with no folio)
  folio_ids = @fund.capital_commitments.where(unit_type:).pluck(:id)
  scope = AccountEntry.where(fund_id: @fund.id, entry_type: NavInputs::MGMT_FEE_ENTRY_TYPE, reporting_date: Date.parse(date),
                             capital_commitment_id: folio_ids)
  expect((scope.sum(:amount_cents).to_d / 100).round(0)).to eq(total.delete(",").to_d)
end

# ---- Settings ----

When('I choose {string} for the evergreen field {string}') do |label, field|
  evergreen_wizard_reveal("[name='evergreen_fund_setting[#{field}]']")
  select(label, from: "evergreen_fund_setting[#{field}]")
end

When('I fill the evergreen field {string} with {string}') do |field, value|
  # For conditional fields: they are shown by the evergreen-settings controller once their trigger is chosen
  fill_in("evergreen_fund_setting[#{field}]", with: value)
end

Then('the evergreen field {string} should be visible') do |field|
  expect(page).to have_field("evergreen_fund_setting[#{field}]", visible: true)
end

Then('the evergreen field {string} should be hidden') do |field|
  expect(page).to have_field("evergreen_fund_setting[#{field}]", visible: :hidden)
end

Then('the fund setting {string} should be {string}') do |attr, value|
  expect(@fund.evergreen_fund_setting.reload.send(attr).to_s).to eq(value)
end

Given('the fund has an open dealing date on {string}') do |date|
  d = Date.parse(date)
  @open_dealing_date = DealingDate.create!(entity_id: @fund.entity_id, fund: @fund, date: d, cutoff_at: d - 5.days,
                                           payment_timing: @fund.evergreen_fund_setting.payment_timing, has_subscriptions: true, status: "open")
end

Given('the fund has a pending subscription order on the open dealing date {string}') do |date|
  steps %(Given the fund has an open dealing date on "#{date}")
  steps %(Given there is an existing investor "name=P Family Trust")
  unit_type = @fund.unit_types_list.first
  evergreen_approved_kyc(@investor)
  DealingOrder.create!(entity_id: @fund.entity_id, fund: @fund, investor: @investor, dealing_date: @open_dealing_date, unit_type:,
                       kind: "subscription", status: "pending", amount_cents: 100_000_000, received_at: Time.current)
end

Given('the fund has a draft NAV for class {string} on {string}') do |unit_type, date|
  FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: Date.parse(date), status: "draft", source: "uploaded",
                  units_outstanding: 1, nav_per_unit_cents: 1_000_000, nav_cents: 1_000_000)
end

Then('the dealing date on {string} should have payment timing {string}') do |date, timing|
  expect(@fund.dealing_dates.find_by!(date: Date.parse(date)).payment_timing).to eq(timing)
end

Then('the fund should have no dealing dates or NAVs') do
  expect(DealingDate.where(fund_id: @fund.id)).not_to exist
  expect(FundNav.where(fund_id: @fund.id)).not_to exist
end

Then('the fund should still be evergreen') do
  @fund.reload.reset_evergreen_cache
  expect(@fund.evergreen?).to be(true)
end

# X116: a refused upload records why on the import upload itself (no row is processed)
Then('the NAV upload should be refused with {string}') do |text|
  expect(@import_upload.reload.status.to_s).to include(text)
  expect(@import_upload.failed_row_count).to eq(@import_upload.total_rows_count)
end
