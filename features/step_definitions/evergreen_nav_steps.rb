# Steps for features/fund/evergreen/nav.feature and the performance-fee part of fees.feature.
# Portfolio fair value is stubbed on NavInputs: valuations and holdings are covered by the existing
# portfolio features; these scenarios test how a NAV is assembled from it.
# Worked examples H3–H6, H29, H30, E7–E11, E38–E44, X5–X9 — openspec/changes/open-ended-funds/design.md#worked-examples

def evergreen_cents(amount)
  (amount.to_s.delete(",").to_d * 100)
end

# New NAV and Override line open a small modal first (Bootstrap; the fields are hidden until then).
# rack_test ignores CSS, so the fields are reachable without opening it. Same idea as
# evergreen_open_fill_modal in evergreen_settlement_steps.rb.
def evergreen_open_nav_modal(action)
  return if Capybara.current_driver == :rack_test

  find("##{action}_open").click
  expect(page).to have_css("##{action}_modal.show")
end

# Approve / Reopen / Recalculate / Delete draft confirm with the "Immediate Actions" popup first
# (JS only — under rack_test the button submits straight away)
def evergreen_nav_proceed
  return if Capybara.current_driver == :rack_test

  within("#confirmModal") { click_on("Proceed") }
end

Given('the evergreen fund {string} with classes {string}') do |name, classes|
  steps %(
    Given there is a fund "name=#{name};currency=INR;unit_types=#{classes}" for the entity
  )
  make_fund_evergreen(@fund, @user)
end

Given('class {string} has the performance fee {string}') do |unit_type, settings|
  term = @fund.evergreen_class_terms.find_by!(unit_type:)
  kv = evergreen_kv(settings)
  term.update!(perf_fee_model: "class_hwm", perf_fee_pct: kv[:pct], hurdle_pct: kv[:hurdle] || 0,
               hurdle_type: kv[:hurdle_type] || "hard", crystallisation: kv[:crystallisation] || "annual")
end

Given('class {string} has no performance fee') do |unit_type|
  @fund.evergreen_class_terms.find_by!(unit_type:).update!(perf_fee_model: "none", perf_fee_pct: 0)
end

Given('class {string} charges a management fee of {string}') do |unit_type, pct|
  FundUnitSetting.find_or_initialize_by(fund: @fund, name: unit_type).update!(entity_id: @fund.entity_id, management_fee: pct)
end

# | investor | folio | class | units | issued |
Given('the evergreen fund has folios:') do |table|
  table.hashes.each do |row|
    steps %(Given there is an existing investor "name=#{row['investor']}")
    cc = CapitalCommitment.new(entity_id: @fund.entity_id, fund: @fund, investor: @investor, unit_type: row["class"],
                               folio_committed_amount_cents: 1_000_000, orig_folio_committed_amount_cents: 1_000_000,
                               folio_id: row["folio"], folio_currency: @fund.currency, fund_close: "Evergreen",
                               commitment_date: Date.parse(row["issued"] || "2025-09-01"),
                               investor_kyc_id: evergreen_approved_kyc(@investor).id)
    cc.save!(validate: false)
    next if row["units"].to_d.zero?

    FundUnit.create!(entity_id: @fund.entity_id, fund: @fund, capital_commitment: cc, investor: @investor, unit_type: row["class"],
                     quantity: row["units"].delete(",").to_d, price_cents: 1_000_000, premium_cents: 0,
                     issue_date: Date.parse(row["issued"] || "2025-09-01"), reason: "Opening units")
  end
end

Given('the portfolio fair value is {string}') do |amount|
  allow_any_instance_of(NavInputs).to receive(:investments_fmv_cents).and_return(evergreen_cents(amount))
end

Given('{string} has no valuation on or before {string}') do |company, date|
  msg = "No valuation for #{company} on or before #{I18n.l(Date.parse(date), format: :day_month_year)} — add one or upload the NAV"
  allow_any_instance_of(NavInputs).to receive(:investments_fmv_cents).and_raise(NavInputs::MissingValuation, msg)
end

Given('the fund ledger has {string} of {string} on {string}') do |name, amount, date|
  AccountEntry.create!(entity_id: @fund.entity_id, fund: @fund, name:, entry_type: "Balance", amount_cents: evergreen_cents(amount),
                       reporting_date: Date.parse(date), period: "As of Date")
end

Given('an approved NAV for class {string} on {string} with NAV per unit {string} and units {string}') do |unit_type, date, per_unit, units|
  FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: Date.parse(date), status: "approved", source: "uploaded",
                  units_outstanding: units.delete(",").to_d, nav_per_unit_cents: evergreen_cents(per_unit),
                  nav_cents: evergreen_cents(per_unit) * units.delete(",").to_d, approved_at: Time.current)
end

Given('the high-water mark of class {string} was set to {string} on {string}') do |unit_type, per_unit, date|
  FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: Date.parse(date), status: "approved", source: "uploaded",
                  units_outstanding: 1, nav_per_unit_cents: evergreen_cents(per_unit), nav_cents: evergreen_cents(per_unit),
                  crystallised: true, hwm_cents: evergreen_cents(per_unit), hwm_after_cents: evergreen_cents(per_unit), approved_at: Time.current)
end

Given('there is an approver {string} in the entity') do |first_name|
  @approver = FactoryBot.create(:user, entity: @user.entity, first_name:)
  @approver.add_role(:approver)
  @approver.add_role(:company_admin)
  @approver.update_columns(curr_role: @user.curr_role)
end

When('the approver logs in') do
  @gp_user ||= @user
  evergreen_fresh_login(@approver)
end

When('I draft the NAV for {string}') do |date|
  evergreen_visit(evergreen_navs_path(@fund))
  evergreen_open_nav_modal("new_nav")
  find("#nav_date").set(Date.parse(date).strftime("%Y-%m-%d"))
  click_on("new_nav")
  # Wait for the request to finish before later steps read the database
  expect(page).to have_content(/NAV drafted|No valuation|approved NAV exists|not evergreen|would be negative/)
end

When('I open the class {string} NAV for {string}') do |unit_type, date|
  @fund_nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  evergreen_visit(evergreen_nav_path(@fund, @fund_nav))
end

When('I override the NAV line {string} to {string} with reason {string}') do |line, value, reason|
  evergreen_open_nav_modal("override")
  select(line, from: "override_line")
  fill_in("override_value", with: value.delete(","))
  fill_in("override_reason", with: reason)
  click_on("override_submit")
  # Wait for the redirect (saved or refused) so the next click isn't on a page mid-reload
  expect(page).to have_content(/Line overridden|can.t be blank|Only a draft|would be negative|no lines to override/)
end

When('I approve the NAV') do
  click_on("approve_nav")
  evergreen_nav_proceed
  # Wait for the request before later steps read the database
  expect(page).to have_content("NAV approved")
end

When('I reopen the NAV') do
  click_on("reopen_nav")
  evergreen_nav_proceed
  expect(page).to have_content("NAV reopened")
end

Then('the class {string} NAV for {string} should be:') do |unit_type, date, table|
  nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  table.rows_hash.each do |field, expected|
    actual = nav.send(field)
    if %w[status source].include?(field) || [true, false].include?(actual)
      expect(actual.to_s).to eq(expected)
    elsif field == "units_outstanding"
      expect(actual.to_d).to eq(expected.delete(",").to_d)
    else
      expect(actual.to_d.round(2)).to eq(evergreen_cents(expected).round(2)), "#{field}: expected #{expected}, got #{actual.to_d / 100}"
    end
  end
end

Then('the NAV per unit shown is {string}') do |value|
  expect(find("#nav_per_unit")).to have_content(value)
end

Then('the NAV line {string} shows the note {string}') do |line, note|
  expect(find("#nav_line_#{line}")).to have_content(note)
end

Then('I should not be able to approve the NAV') do
  expect(page).not_to have_css("#approve_nav")
  expect(page).to have_content("Needs the approver role")
end

When('the preparer tries to approve the NAV directly') do
  @nav_result = FundNavApprove.call(fund_nav: FundNav.find(@fund_nav.id), current_user: @user)
end

Then('the approval is refused with {string}') do |msg|
  expect(@nav_result.success?).to be(false)
  expect(@nav_result[:errors]).to eq(msg)
end

Given('a confirmed dealing date on {string} priced at that NAV') do |date|
  d = Date.parse(date)
  dd = DealingDate.create!(entity_id: @fund.entity_id, fund: @fund, date: d, cutoff_at: d - 5.days, payment_timing: "before",
                           has_subscriptions: true, status: "confirmed", confirmed_at: Time.current)
  order = DealingOrder.create!(entity_id: @fund.entity_id, fund: @fund, investor: Investor.where(entity_id: @fund.entity_id).first,
                               dealing_date: dd, unit_type: @fund_nav.unit_type, kind: "subscription", status: "dealt",
                               amount_cents: 100, received_at: d - 10.days)
  DealingFill.create!(entity_id: @fund.entity_id, fund: @fund, dealing_date: dd, dealing_order: order, fund_nav: @fund_nav,
                      kind: "subscription", unit_type: @fund_nav.unit_type, nav_per_unit_cents: @fund_nav.nav_per_unit_cents)
end

When('a portfolio input dated {string} changes') do |date|
  AccountEntry.create!(entity_id: @fund.entity_id, fund: @fund, name: "Late Adjustment", entry_type: "Balance", amount_cents: 100,
                       reporting_date: Date.parse(date), period: "As of Date")
end

When('a fund unit dated {string} is added') do |date|
  cc = @fund.capital_commitments.first
  FundUnit.create!(entity_id: @fund.entity_id, fund: @fund, capital_commitment: cc, investor: cc.investor, unit_type: cc.unit_type,
                   quantity: 1, price_cents: 1_000_000, premium_cents: 0, issue_date: Date.parse(date), reason: "Late unit")
end

When('I upload the NAV rows:') do |table|
  path = Rails.root.join("tmp/evergreen_nav_upload_#{SecureRandom.hex(4)}.xlsx")
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "NAV") do |sheet|
      sheet.add_row(ImportFundNav::STANDARD_HEADERS)
      table.raw.drop(1).each { |r| sheet.add_row(r) }
    end
    p.serialize(path.to_s)
  end
  @import_upload = ImportUpload.create!(name: "NAV upload", entity_id: @fund.entity_id, owner: @fund, user: @user,
                                        import_type: "FundNav", import_file: File.open(path))
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
end

Then('the NAV upload should have {string} failed rows') do |count|
  results = lambda do
    file = @import_upload.reload.import_results&.download
    file ? Roo::Spreadsheet.open(file.path, extension: :xlsx).sheet(0).to_a.map { |r| r.compact.join(" | ") } : @import_upload.error_text
  end
  expect(@import_upload.failed_row_count).to eq(count.to_i), -> { "results: #{results.call.inspect}" }
end

Then('the NAV upload results should mention {string}') do |text|
  file = @import_upload.reload.import_results.download
  rows = Roo::Spreadsheet.open(file.path, extension: :xlsx).sheet(0).to_a.flatten.compact.map(&:to_s)
  expect(rows.join(" | ")).to include(text)
end

Then('the crystallised performance fee entries for {string} total {string} across {string} folios') do |date, total, folios|
  scope = AccountEntry.where(fund_id: @fund.id, reporting_date: Date.parse(date), name: Crystalliser::ENTRY_NAME)
  expect(scope.sum(:amount_cents).to_d.round(0)).to eq(evergreen_cents(total).round(0))
  expect(scope.count).to eq(folios.to_i)
end

Then('the high-water mark of class {string} before {string} is {string}') do |unit_type, date, mark|
  hwm, = NavInputs.new(@fund.reload, Date.parse(date)).high_water_mark(unit_type)
  expect(hwm.to_d.round(2)).to eq(evergreen_cents(mark))
end

# Phase 7: management fee on NAV
Given('the management fee formula is added') do
  EvergreenFeeFormulaSeed.call(@fund)
end

Then('the management fee entries for {string} should total {string}') do |date, total|
  # Folio entries only: the allocation run also writes a fund-level cumulative total (no folio)
  scope = AccountEntry.where(fund_id: @fund.id, entry_type: NavInputs::MGMT_FEE_ENTRY_TYPE, reporting_date: Date.parse(date))
                      .where.not(capital_commitment_id: nil)
  breakdown = scope.pluck(:name, :folio_id, :capital_commitment_id, :amount_cents, :cumulative, :fund_formula_id)
  expect((scope.sum(:amount_cents).to_d / 100).round(0)).to eq(total.delete(",").to_d), "entries: #{breakdown.inspect}"
end

Given('folio {string} accrued a management fee of {string} on {string}') do |folio, amount, date|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  AccountEntry.create!(entity_id: @fund.entity_id, fund: @fund, capital_commitment: cc, investor_id: cc.investor_id, folio_id: folio,
                       name: EvergreenFeeFormulaSeed::NAME, entry_type: NavInputs::MGMT_FEE_ENTRY_TYPE, amount_cents: evergreen_cents(amount),
                       reporting_date: Date.parse(date), period: "As of Date", generated: true)
end

When('the class {string} NAV for {string} is drafted and approved') do |unit_type, date|
  result = FundNavBuilder.call(fund: @fund.reload, nav_date: Date.parse(date), current_user: @user)
  raise "draft failed: #{result[:errors]}" unless result.success?

  nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  approver = @approver || FactoryBot.create(:user, entity: @user.entity).tap { |u| u.add_role(:approver) }
  @approver = approver
  approved = FundNavApprove.call(fund_nav: nav, current_user: approver)
  raise "approve failed: #{approved[:errors]}" unless approved.success?
end

Then('the NAV audit trail for class {string} on {string} should note {string}') do |unit_type, date, note|
  nav = FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
  expect(nav.audits.pluck(:comment).compact.join(" | ")).to include(note)
end

# A NAV approved before R9.2 blocked approval without the fee (legacy data, E318–E320): drafted from the
# ledger, then marked approved directly — FundNavApprove would now refuse it
Given('the class {string} NAV for {string} was drafted and approved before a fee was required') do |_unit_type, date|
  result = FundNavBuilder.call(fund: @fund.reload, nav_date: Date.parse(date), current_user: @user)
  raise "draft failed: #{result[:errors]}" unless result.success?

  FundNav.where(fund: @fund, nav_date: Date.parse(date)).find_each { |nav| nav.update_columns(status: "approved", approved_at: Time.current) }
end
