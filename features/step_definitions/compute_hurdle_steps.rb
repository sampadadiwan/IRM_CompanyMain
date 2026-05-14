# Setup: assign hurdle_rate in json_fields for a named fund unit setting
Given('the fund unit setting {string} has a hurdle rate of {string}') do |unit_name, rate|
  fus = FundUnitSetting.find_or_initialize_by(name: unit_name, fund: @fund)
  fus.entity ||= @fund.entity
  fus.save!
  fus.update!(json_fields: fus.json_fields.merge('hurdle_rate' => rate))
  @fund_unit_setting = fus
end

# Setup: create a CapitalCall -> CapitalRemittance -> CapitalRemittancePayment chain
# so that the commitment's capital_remittance_payments includes this payment.
Given('there is a hurdle remittance payment of {string} for the commitment') do |args|
  capital_call = FactoryBot.create(:capital_call,
    fund: @fund,
    entity: @fund.entity,
    call_basis: 'Upload',
    name: "Hurdle Test Call #{Time.now.to_f}"
  )

  remittance = FactoryBot.create(:capital_remittance,
    capital_call: capital_call,
    capital_commitment: @capital_commitment,
    fund: @fund,
    entity: @fund.entity,
    investor: @capital_commitment.investor,
    folio_id: "HURDLE-#{SecureRandom.hex(4)}",
    folio_committed_amount_cents: @capital_commitment.orig_folio_committed_amount_cents,
    committed_amount_cents: @capital_commitment.orig_folio_committed_amount_cents,
    status: 'Paid'
  )

  payment = FactoryBot.build(:capital_remittance_payment,
    capital_remittance: remittance,
    fund: @fund,
    entity: @fund.entity,
    payment_date: Date.today
  )
  key_values(payment, args)
  payment.save!
  @hurdle_remittance_payment = payment
end

# Setup: create a CapitalDistributionPayment for the commitment.
# folio_id must match the commitment's folio_id so that the before_validation
# :ensure_commitment callback can look it up via fund.capital_commitments.where(investor_id:, folio_id:).
Given('there is a hurdle distribution payment of {string} for the commitment') do |args|
  distribution = FactoryBot.create(:capital_distribution,
    fund: @fund,
    entity: @fund.entity,
    income_cents: 0,
    cost_of_investment_cents: 0,
    reinvestment_cents: 0,
    distribution_date: Date.today,
    title: "Hurdle Test Distribution #{Time.now.to_f}",
    generate_payments: false
  )

  payment = FactoryBot.build(:capital_distribution_payment,
    capital_distribution: distribution,
    capital_commitment: @capital_commitment,
    fund: @fund,
    entity: @fund.entity,
    investor: @capital_commitment.investor,
    folio_id: @capital_commitment.folio_id,
    payment_date: Date.today
  )
  key_values(payment, args)
  payment.save!
  @hurdle_distribution_payment = payment
end

# Verification: compute_hurdle with specified flags and compare to expected cents
Then('the compute_hurdle for the commitment as of {string} should equal {string} cents') do |date, expected|
  result = @capital_commitment.compute_hurdle(date)
  expect(result.round(0).to_i).to eq(expected.to_i),
    "Expected hurdle #{expected} cents but got #{result.round(0).to_i}"
end

Then('the compute_hurdle with use_distributions for the commitment as of {string} should equal {string} cents') do |date, expected|
  result = @capital_commitment.compute_hurdle(date, use_distributions: true)
  expect(result.round(0).to_i).to eq(expected.to_i),
    "Expected hurdle with distributions #{expected} cents but got #{result.round(0).to_i}"
end

Then('the compute_hurdle with use_tracking_currency for the commitment as of {string} should equal {string} cents') do |date, expected|
  result = @capital_commitment.compute_hurdle(date, use_tracking_currency: true)
  expect(result.round(0).to_i).to eq(expected.to_i),
    "Expected tracking currency hurdle #{expected} cents but got #{result.round(0).to_i}"
end

Then('the compute_hurdle with use_tracking_currency and use_distributions for the commitment as of {string} should equal {string} cents') do |date, expected|
  result = @capital_commitment.compute_hurdle(date, use_tracking_currency: true, use_distributions: true)
  expect(result.round(0).to_i).to eq(expected.to_i),
    "Expected tracking currency hurdle with distributions #{expected} cents but got #{result.round(0).to_i}"
end
