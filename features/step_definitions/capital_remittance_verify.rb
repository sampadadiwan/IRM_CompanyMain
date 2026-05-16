# Step definitions for capital remittance verify confirmation popup scenarios

Given('the remittances are paid') do
  # Pay each remittance at exactly 100% of the call amount without verifying
  @capital_call.capital_remittances.each do |cr|
    crp = cr.capital_remittance_payments.new(
      fund_id: cr.fund_id,
      entity_id: cr.entity_id,
      folio_amount_cents: cr.folio_call_amount_cents,
      payment_date: cr.remittance_date
    )
    CapitalRemittancePaymentCreate.wtf?(capital_remittance_payment: crp)
    cr.reload
  end
end

Given('the remittances are paid at {int} percent of the call amount') do |percent|
  # Pay each remittance at the given percentage of the call amount without verifying
  @capital_call.capital_remittances.each do |cr|
    folio_amount_cents = cr.folio_call_amount_cents * (percent.to_d / 100)
    crp = cr.capital_remittance_payments.new(
      fund_id: cr.fund_id,
      entity_id: cr.entity_id,
      folio_amount_cents: folio_amount_cents,
      payment_date: cr.remittance_date
    )
    CapitalRemittancePaymentCreate.wtf?(capital_remittance_payment: crp)
    cr.reload
  end
end

Given('the first remittance is verified') do
  @remittance = @capital_call.capital_remittances.first
  CapitalRemittanceVerify.call(capital_remittance: @remittance)
  @remittance.reload
end

When('I click verify on the first remittance') do
  @remittance = @capital_call.capital_remittances.first
  visit(capital_call_url(@capital_call))
  click_on "Remittances"
  within("#capital_remittance_#{@remittance.id}") do
    click_on "Actions"
    click_on "Verify"
  end
end

When('I click unverify on the first remittance') do
  @remittance ||= @capital_call.capital_remittances.first
  visit(capital_call_url(@capital_call))
  click_on "Remittances"
  within("#capital_remittance_#{@remittance.id}") do
    click_on "Actions"
    click_on "Unverify"
  end
end

Then('the verify confirmation popup should contain {string}') do |text|
  expect(page).to have_css('#confirmModal', visible: true)
  within('#confirmModal') do
    expect(page).to have_content(text)
  end
end

Then('the verify confirmation popup should not contain {string}') do |text|
  within('#confirmModal') do
    expect(page).not_to have_content(text)
  end
end

When('I proceed with the remittance verification') do
  click_on "Proceed"
end
