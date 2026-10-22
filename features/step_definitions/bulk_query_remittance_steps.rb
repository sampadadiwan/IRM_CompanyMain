# Steps for features/fund/bulk_query_remittances.feature (bulk-path-query-optimisation, phase 2).
# Setup reuses capital_call_live_remittances_steps.rb ("there is a capital call {string} whose remittances
# are not generated yet", "the call's remittances are generated"); query counts use query_budget_steps.rb.

# The capital_call factory picks a random close percentage (test/factories.rb), which wins over
# percentage_called - pin both so the expected amounts are known
Given('the call asks for {int}% from every close') do |percent|
  @capital_call.update_columns(percentage_called: percent, close_percentages: { "First Close" => percent })
end

# H2: generation then also creates a payment per remittance, and each payment unverifies its remittance
Given('the call generates its remittances already verified') do
  @capital_call.update_column(:generate_remittances_verified, true)
end

Then('each remittance of the call should be called at {int}% of its commitment') do |percent|
  remittances = @capital_call.capital_remittances
  expect(remittances.count).to eq(@fund.capital_commitments.count)
  remittances.each do |cr|
    # committed_amount_cents is the remittance's own snapshot of its commitment (set_call_amount)
    expect(cr.call_amount_cents).to eq(cr.committed_amount_cents * percent / 100)
  end
end

Then('each remittance of the call should have one payment of its call amount') do
  @capital_call.capital_remittances.includes(:capital_remittance_payments).find_each do |cr|
    expect(cr.capital_remittance_payments.size).to eq(1)
    expect(cr.capital_remittance_payments.first.amount_cents).to eq(cr.call_amount_cents)
  end
end

# H2: each document is validated on the remittance's save (validates_associated :documents) - with 3 of
# them, loading their folders/signatures one by one is what the un-verify preload removes
Given('the first remittance of the call has {int} documents') do |count|
  @first_remittance = @capital_call.capital_remittances.order(:id).first
  count.times do |i|
    FactoryBot.create(:document, name: "Receipt #{i + 1}", entity: @first_remittance.entity, owner: @first_remittance,
                                 folder: @first_remittance.document_folder, user: @user)
  end
end

# X1: a document attached to the first remittance that fails its own validation (name is required).
# Written with update_column so the bad state exists without a save that would refuse it.
Given('the first remittance of the call has a document that is no longer valid') do
  @first_remittance = @capital_call.capital_remittances.order(:id).first
  doc = FactoryBot.create(:document, name: "Call Notice", entity: @first_remittance.entity, owner: @first_remittance,
                                     folder: @first_remittance.document_folder, user: @user)
  doc.update_column(:name, nil)
end

# X1: a payment's after_commit (CapitalRemittancePayment#unverify_remittance) re-saves the remittance, whose
# set_payment_date takes the latest payment's date - a far-future date, so a successful save would show it
When('a payment dated {string} is recorded for the first remittance of the call') do |date|
  @first_remittance = (@first_remittance || @capital_call.capital_remittances.order(:id).first).reload
  @payment_date_before = @first_remittance.payment_date
  crp = CapitalRemittancePayment.new(capital_remittance: @first_remittance, fund_id: @first_remittance.fund_id,
                                     entity_id: @first_remittance.entity_id, amount_cents: 100,
                                     folio_amount_cents: 100, payment_date: Date.parse(date))
  CapitalRemittancePaymentCreate.call(capital_remittance_payment: crp)
end

# X1: the invalid document still blocks the remittance's save, so its payment date is unchanged
Then("the first remittance of the call should keep its payment date") do
  expect(@first_remittance.reload.payment_date).to eq(@payment_date_before)
end

# X1 control: without the invalid document the same payment does move the payment date
Then('the first remittance of the call should have payment date {string}') do |date|
  expect(@first_remittance.reload.payment_date).to eq(Date.parse(date))
end

# H8: the fund's updated_at, to see whether a later run touched it (sub-second precision varies by DB, so
# compare to the second and step the clock past it)
Given("I note the fund's last update") do
  @fund_updated_at = @fund.reload.updated_at
  travel 2.seconds
end

Then("the fund should not have been touched") do
  expect(@fund.reload.updated_at.to_i).to eq(@fund_updated_at.to_i)
end

Then("the fund should have been touched") do
  expect(@fund.reload.updated_at.to_i).to be > @fund_updated_at.to_i
end

# H9 (phase 8): the custom-fields form a new remittance gets from its entity
Given('the entity has a capital remittance form') do
  @remittance_form_type = FormType.find_or_create_by!(entity: @capital_call.entity, name: "CapitalRemittance", tag: "Default")
end

# E12 (phase 8): no form at all - remittances are created without one, as before
Given('the entity has no capital remittance form') do
  FormType.where(entity: @capital_call.entity, name: "CapitalRemittance").find_each(&:destroy!)
  @remittance_form_type = nil
end

Then('every remittance of the call should have that form') do
  expect(@capital_call.capital_remittances.count).to eq(@fund.capital_commitments.count)
  expect(@capital_call.capital_remittances.pluck(:form_type_id).uniq).to eq([@remittance_form_type&.id])
end
