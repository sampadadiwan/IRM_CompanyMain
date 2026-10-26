# The fund's money figures as of a date (features/fund/fund_as_of_amounts.feature).
# Expectations are read from the rows that were created, so a callback that adjusts an amount cannot make a scenario lie.

AS_OF_PERIOD_END = Date.new(2026, 9, 30)

# Dates for the "after" scenarios: some rows fall on or before AS_OF_PERIOD_END and one of each kind falls after it
AS_OF_AFTER_DATES = {
  commitment: "2026-02-01", late_commitment: "2026-10-10", call: "2026-09-01",
  early_payment: "2026-09-15", late_payment: "2026-10-05",
  early_distribution: "2026-09-20", late_distribution: "2026-10-05",
  early_unit: "2026-09-01", late_unit: "2026-11-01"
}.freeze

# Every row dated in the past, so asking for today leaves nothing out
AS_OF_PAST_DATES = {
  commitment: "2026-01-05", late_commitment: "2026-01-20", call: "2026-02-01",
  early_payment: "2026-02-10", late_payment: "2026-02-20",
  early_distribution: "2026-03-01", late_distribution: "2026-03-10",
  early_unit: "2026-02-05", late_unit: "2026-02-15"
}.freeze

def as_of_commitment(fund, investor, folio_id, crore, date)
  FactoryBot.create(:capital_commitment, fund:, entity: fund.entity, investor:, folio_id:,
                                         orig_folio_committed_amount_cents: crore_cents(crore), folio_committed_amount_cents: crore_cents(crore),
                                         orig_committed_amount_cents: crore_cents(crore), committed_amount_cents: crore_cents(crore),
                                         commitment_date: Date.parse(date))
end

def as_of_remittance(call, commitment, investor, date)
  FactoryBot.create(:capital_remittance, fund: call.fund, entity: call.fund.entity, capital_call: call, capital_commitment: commitment,
                                         investor:, folio_id: commitment.folio_id, folio_committed_amount_cents: commitment.folio_committed_amount_cents,
                                         call_amount_cents: crore_cents(100), folio_call_amount_cents: crore_cents(100),
                                         collected_amount_cents: 0, folio_collected_amount_cents: 0,
                                         verified: false, remittance_date: Date.parse(date), status: "Pending")
end

def as_of_payment(remittance, crore, date)
  FactoryBot.create(:capital_remittance_payment, fund: remittance.fund, entity: remittance.fund.entity, capital_remittance: remittance,
                                                 folio_amount_cents: crore_cents(crore), amount_cents: crore_cents(crore), payment_date: Date.parse(date))
end

def as_of_distribution_payment(distribution, commitment, investor, crore, date)
  FactoryBot.create(:capital_distribution_payment, fund: distribution.fund, entity: distribution.fund.entity, capital_distribution: distribution,
                                                   investor:, folio_id: commitment.folio_id, gross_payable_cents: crore_cents(crore),
                                                   payment_date: Date.parse(date))
end

def as_of_unit(commitment, investor, crore, date)
  FactoryBot.create(:fund_unit, fund: commitment.fund, entity: commitment.fund.entity, investor:, capital_commitment: commitment,
                                issue_date: Date.parse(date), total_premium_cents: crore_cents(crore))
end

# Commitments of 450 and 52 Cr by the date and 20 Cr after it (502 Cr as of 30 September), a verified payment of 125.5 Cr
# and one of 5 Cr after the date, an unverified payment of 3 Cr
# Three commitments (one dated late), one call with a verified and an unverified remittance, payments before and after the
# date, two distribution payments and two fund units, all through the same factories the other fund features use
def build_fund_money_fixture(dates, fund: nil)
  entity = @user.entity
  @fund = fund || FactoryBot.create(:fund, entity:, name: "Money Fund", currency: "INR")
  investor_entity = FactoryBot.create(:entity, entity_type: "Investor")
  investor = FactoryBot.create(:investor, entity:, investor_entity:, investor_name: "Fund Money Investor")
  call = FactoryBot.create(:capital_call, fund: @fund, entity:, call_date: Date.parse(dates[:call]), due_date: Date.parse(dates[:call]) + 3.weeks)
  call.update_column(:approved, true) # verifying a remittance needs an approved call

  commitment = as_of_commitment(@fund, investor, "F-C1", 450, dates[:commitment])
  unverified_commitment = as_of_commitment(@fund, investor, "F-C3", 52, dates[:commitment])
  @late_commitment = as_of_commitment(@fund, investor, "F-C2", 20, dates[:late_commitment])

  verified = as_of_remittance(call, commitment, investor, dates[:call])
  unverified = as_of_remittance(call, unverified_commitment, investor, dates[:call])
  @early_payment = as_of_payment(verified, 125.5, dates[:early_payment])
  @late_payment = as_of_payment(verified, 5, dates[:late_payment])
  @unverified_payment = as_of_payment(unverified, 3, dates[:early_payment])
  # A payment un-verifies its remittance, so verify once the payments are in, as the fund team does
  CapitalRemittanceVerify.call(capital_remittance: verified.reload, current_user: @user)

  distribution = FactoryBot.create(:capital_distribution, fund: @fund, entity:, generate_payments: false,
                                                          distribution_date: Date.parse(dates[:early_distribution]))
  @early_distribution = as_of_distribution_payment(distribution, commitment, investor, 4, dates[:early_distribution])
  @late_distribution = as_of_distribution_payment(distribution, unverified_commitment, investor, 6, dates[:late_distribution])

  @early_unit = as_of_unit(commitment, investor, 2, dates[:early_unit])
  @late_unit = as_of_unit(commitment, investor, 1, dates[:late_unit])
  @fund.reload
end

Given('a fund with commitments, collections, distributions and units, some dated after 30 September 2026') do
  build_fund_money_fixture(AS_OF_AFTER_DATES)
end

Given('a fund with commitments, collections, distributions and units all dated in the past') do
  build_fund_money_fixture(AS_OF_PAST_DATES)
end

When('the fund is viewed as of {string}') do |date|
  @as_of = @fund.as_of(date == "today" ? Time.zone.today : Date.parse(date))
end

# H18 — Happy path: for today every as-of figure is the fund's own running total
Then("each as-of figure equals the fund's own figure") do
  expect(@as_of.committed_amount).to eq(@fund.committed_amount)
  expect(@as_of.call_amount).to eq(@fund.call_amount)
  expect(@as_of.collected_amount).to eq(@fund.collected_amount)
  expect(@as_of.distribution_amount).to eq(@fund.distribution_amount)
  expect(@as_of.total_units_premium).to eq(@fund.total_units_premium)
  expect(@fund.collected_amount_cents).to be_positive
  expect(@fund.distribution_amount_cents).to be_positive
end

# E27
Then('the committed amount leaves out the commitment dated after that day') do
  expected = CapitalCommitment.where(fund_id: @fund.id, commitment_date: ..AS_OF_PERIOD_END).sum(:committed_amount_cents)
  expect(@late_commitment.reload.committed_amount_cents).to be_positive
  expect(@as_of.committed_amount.cents).to eq(expected)
  expect(@as_of.committed_amount.cents).to be < @fund.committed_amount_cents
end

# E28
Then('the collected amount leaves out the payment received after that day') do
  verified_early = @early_payment.reload.amount_cents
  expect(@late_payment.reload.amount_cents).to be_positive
  expect(@as_of.collected_amount.cents).to eq(verified_early)
  expect(@as_of.collected_amount.cents).to be < @fund.collected_amount_cents
end

# E29
Then('the collected amount leaves out the payment on the unverified remittance') do
  expect(@unverified_payment.reload.amount_cents).to be_positive
  expect(@as_of.collected_amount.cents).to eq(@early_payment.reload.amount_cents)
end

# E30
Then('the distribution amount leaves out the distribution payment dated after that day') do
  expect(@late_distribution.reload.gross_payable_cents).to be_positive
  expect(@as_of.distribution_amount.cents).to eq(@early_distribution.reload.gross_payable_cents)
  expect(@as_of.distribution_amount.cents).to be < @fund.distribution_amount_cents
end

# E31
Then('the total units premium leaves out the unit issued after that day') do
  expect(@late_unit.reload.total_premium_cents).to be_positive
  expect(@as_of.total_units_premium.cents).to eq(@early_unit.reload.total_premium_cents)
  expect(@as_of.total_units_premium.cents).to be < @fund.total_units_premium_cents
end
