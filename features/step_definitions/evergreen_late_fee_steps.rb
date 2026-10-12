# Late management fees (openspec/changes/archive/2026-10-11-evergreen-late-management-fees): approval refusals (R9.2, R9.13),
# late-fee decisions and the late-fees panel. Worked examples H105–H108, E329–E345, X204–X208.

# Shares @approver with evergreen_nav_steps.rb ("is drafted and approved"), so one approver acts throughout
def approver
  @approver ||= FactoryBot.create(:user, entity: @user.entity).tap { |u| u.add_role(:approver) }
end

def evergreen_class_nav(unit_type, date)
  FundNav.find_by!(fund: @fund, unit_type:, nav_date: Date.parse(date))
end

# H108, X208, E342–E345: approve through the service, as the controller does
Then('approving the class {string} NAV for {string} is refused with {string}') do |unit_type, date, message|
  nav = evergreen_class_nav(unit_type, date)
  result = FundNavApprove.call(fund_nav: nav, current_user: approver)
  expect(result.success?).to be(false)
  expect(result[:errors]).to eq(message)
  expect(nav.reload).to be_draft
end

Then('approving the class {string} NAV for {string} succeeds') do |unit_type, date|
  nav = evergreen_class_nav(unit_type, date)
  result = FundNavApprove.call(fund_nav: nav, current_user: approver)
  expect(result.success?).to be(true), "approval refused: #{result[:errors]}"
  expect(nav.reload).to be_approved
end

# X208: the NAV page shows the reason beside a disabled Approve
Then('the Approve button should be disabled') do
  expect(page).to have_css("#approve_nav_disabled")
  expect(page).to have_no_css("#approve_nav")
end

# E343: an administrator's upload, still a draft
Given('an uploaded draft NAV for class {string} on {string} with NAV per unit {string} and units {string}') do |unit_type, date, per_unit, units|
  FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: Date.parse(date), status: "draft", source: "uploaded",
                  units_outstanding: units.delete(",").to_d, nav_per_unit_cents: evergreen_cents(per_unit),
                  nav_cents: evergreen_cents(per_unit) * units.delete(",").to_d)
end

# E344: a class's first NAV, drafted at its initial price with nothing outstanding
Given('a computed draft NAV for class {string} on {string} with no units outstanding') do |unit_type, date|
  FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: Date.parse(date), status: "draft", source: "computed",
                  units_outstanding: 0, nav_per_unit_cents: 1_000_000, nav_cents: 0)
end

# Drafts every class for the date through the builder (no browser), as Recalculate does
When('the NAVs for {string} are drafted') do |date|
  result = FundNavBuilder.call(fund: @fund.reload, nav_date: Date.parse(date), current_user: @user)
  raise "draft failed: #{result[:errors]}" unless result.success?
end

# H105, E329, E333: the late accruals the draft still needs a decision on (R9.12, R9.13)
Then('the class {string} draft for {string} should have a late fee of {string} waiting for a decision') do |unit_type, date, amount|
  nav = evergreen_class_nav(unit_type, date)
  late = EvergreenLateFees.call(@fund, unit_type, nav.nav_date, draft: nav)
  expect(late.outstanding_cents.round(2)).to eq(evergreen_cents(amount).round(2))
end

# E330–E333, E336: nothing late for the class
Then('the class {string} draft for {string} should have no late fee') do |unit_type, date|
  nav = evergreen_class_nav(unit_type, date)
  expect(EvergreenLateFees.call(@fund, unit_type, nav.nav_date, draft: nav).late_cents).to eq(0)
end

# E336: the fund's late payments the date's drafts took in (R9.17)
Then('the {string} drafts should include a late fee payment of {string}') do |date, amount|
  FundNav.where(fund: @fund, nav_date: Date.parse(date)).find_each do |nav|
    expect(nav.breakdown.to_h["late_mgmt_fee_paid_cents"].to_d.round(2)).to eq(evergreen_cents(amount).round(2))
  end
end

# The shared setup of the phase-3 scenarios (design Part 4): 30 Sep approved with no fee, a late fee dated
# in its period, October's own fee, and the 31 Oct drafts
Given('class {string} has a late fee of {string} dated {string} on its {string} draft, with {string} accrued for October') do |unit_type, late, late_date, draft_date, october|
  folio = @fund.capital_commitments.find_by!(unit_type:).folio_id
  steps %(
    Given class "#{unit_type}" charges a management fee of "1.5"
    And the class "#{unit_type}" NAV for "#{late_date}" was drafted and approved before a fee was required
    And folio "#{folio}" accrued a management fee of "#{late}" on "#{late_date}"
    And folio "#{folio}" accrued a management fee of "#{october}" on "#{draft_date}"
    When the NAVs for "#{draft_date}" are drafted
  )
end

def decide_late_fee(unit_type, date, choice, reason, user)
  FundNavLateFeeDecision.call(fund_nav: evergreen_class_nav(unit_type, date), choice:, reason:, current_user: user)
end

When('the approver decides to {string} the late fee on the class {string} NAV for {string}') do |choice, unit_type, date|
  result = decide_late_fee(unit_type, date, choice, "", approver)
  raise "decision refused: #{result[:errors]}" unless result.success?
end

When('the approver decides to {string} the late fee on the class {string} NAV for {string} with reason {string}') do |choice, unit_type, date, reason|
  result = decide_late_fee(unit_type, date, choice, reason, approver)
  raise "decision refused: #{result[:errors]}" unless result.success?
end

# X205 / X206: the operation refuses whoever asks
Then('deciding to {string} the late fee on the class {string} NAV for {string} as myself is refused with {string}') do |choice, unit_type, date, message|
  result = decide_late_fee(unit_type, date, choice, "", @user)
  expect(result[:errors]).to eq(message)
end

Then('deciding to {string} the late fee on the class {string} NAV for {string} as the approver is refused with {string}') do |choice, unit_type, date, message|
  result = decide_late_fee(unit_type, date, choice, "", approver)
  expect(result[:errors]).to eq(message)
end

# H106, X204: through the NAV page's Decide form (Save is the confirmation)
When('I decide to {string} the late fee') do |choice|
  within("#late_fee_form") do
    choose("late_fee_#{choice}")
    click_on("late_fee_submit")
  end
end

Then('the class {string} draft for {string} should have no late fee waiting for a decision') do |unit_type, date|
  nav = evergreen_class_nav(unit_type, date)
  expect(EvergreenLateFees.call(@fund, unit_type, nav.nav_date, draft: nav).outstanding_cents).to eq(0)
end

# E338: one dealt redemption per folio on a confirmed dealing date
Given('folios {string} redeemed on dealing date {string}') do |folios, date|
  d = Date.parse(date)
  dd = DealingDate.find_by(fund: @fund, date: d) ||
       DealingDate.create!(entity_id: @fund.entity_id, fund: @fund, date: d, cutoff_at: d - 5.days, payment_timing: "before",
                           has_redemptions: true, status: "confirmed", confirmed_at: Time.current)
  folios.split(",").each do |folio_id|
    cc = @fund.capital_commitments.find_by!(folio_id:)
    order = DealingOrder.create!(entity_id: @fund.entity_id, fund: @fund, investor: cc.investor, capital_commitment: cc, dealing_date: dd,
                                 unit_type: cc.unit_type, kind: "redemption", status: "dealt", units: 10, received_at: d - 10.days)
    DealingFill.create!(entity_id: @fund.entity_id, fund: @fund, dealing_date: dd, dealing_order: order, kind: "redemption",
                        unit_type: cc.unit_type, units: 10, amount_cents: 10_000_00, nav_per_unit_cents: 10_000_00)
  end
end
