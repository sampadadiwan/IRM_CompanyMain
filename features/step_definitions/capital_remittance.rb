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


Then('I should be able to see my capital remittances') do
  click_on("Calls")
  CapitalRemittance.all.each do |cc|
    puts "checking capital remittance for #{cc.investor.investor_name} against #{@investor.investor_name} "
    if cc.investor_id == @investor.id
      puts "Call Visible"
      expect(page).to have_content(@investor.investor_name) if @user.curr_role != "investor"
      expect(page).to have_content( money_to_currency(cc.due_amount) )
      expect(page).to have_content( money_to_currency(cc.collected_amount) )
    else
      puts "Call Not Visible"
      expect(page).not_to have_content(cc.investor.investor_name)
    end
  end
end

Given('the remittances are paid and verified') do
  CapitalRemittance.all.each do |cr|
    cr.update(folio_collected_amount_cents: cr.folio_call_amount_cents, collected_amount_cents: cr.call_amount_cents, verified: true)
  end
end

Given('the remittances are overpaid and verified') do
  CapitalRemittance.all.each do |cr|
    cr.update(folio_collected_amount_cents: cr.folio_call_amount_cents + 1000, collected_amount_cents: cr.call_amount_cents + 1000, verified: true)
  end
end

Given('the remittances are verified') do
  CapitalRemittance.all.each do |cr|
    CapitalRemittanceVerify.wtf?(capital_remittance: cr)
  end
end

Then('the remittances have verified set to {string}') do |flag|
  CapitalRemittance.all.each do |cr|
    cr.verified.should == (flag == "true")
  end
end

Given('there are payments for each remittance') do
  CapitalRemittance.all.each do |cr|
    unless cr.capital_remittance_payments.exists?
      cr.capital_remittance_payments.create!(fund_id: cr.fund_id, entity_id: cr.entity_id, folio_amount_cents: cr.folio_call_amount_cents, payment_date: cr.remittance_date)
    end
  end
end

Given('remittances are paid {string} and verified') do |paid_percentage|
  @latest_payment = {}
  @fund.capital_remittances.each do |cr|
    # Calculate the folio amount to be paid based on the given percentage
    folio_amount_cents = cr.folio_call_amount_cents * (paid_percentage.to_d / 100)

    # Create a new payment for the capital remittance
    crp = cr.capital_remittance_payments.new(
      fund_id: cr.fund_id,
      entity_id: cr.entity_id,
      folio_amount_cents: folio_amount_cents,
      payment_date: cr.remittance_date
    )

    result = CapitalRemittancePaymentCreate.wtf?(capital_remittance_payment: crp)

    # Store the latest   payment amount for the remittance
    @latest_payment[cr.id] = crp.amount_cents

    # Verify the capital remittance after the payment
    result = CapitalRemittanceVerify.call(capital_remittance: cr)
    result.success?.should == true
  end
end

When('I edit the remittance payment with convert_to_fund_currency {string}') do |string|
  @convert_to_fund_currency = string == "true"
  @target_remittance_payment = CapitalRemittancePayment.where(convert_to_fund_currency: @convert_to_fund_currency).first
  visit(edit_capital_remittance_payment_path(@target_remittance_payment))
  @amount = @target_remittance_payment.amount.to_f
  @folio_amount = @target_remittance_payment.folio_amount.to_f * 5
  fill_in("capital_remittance_payment_folio_amount", with: @folio_amount) if @convert_to_fund_currency
  fill_in("capital_remittance_payment_notes", with: "Test edit remittance payment")
  click_on("Save")
  expect(page).to have_content("Capital remittance payment was successfully updated")
end

Then('the capital remittance payment amount is recomputed') do
  @target_remittance_payment.reload
  puts "Checking remittance payment amount #{@target_remittance_payment.amount} against folio amount #{@target_remittance_payment.folio_amount}"
  expect(@target_remittance_payment.folio_amount.to_f).to eq(@folio_amount)
  expect(@target_remittance_payment.amount.to_f).not_to eq(@amount)
end

Then('the capital remittance payment amount is not recomputed') do
  @target_remittance_payment.reload
  puts "Checking remittance payment amount #{@target_remittance_payment.amount} against folio amount #{@target_remittance_payment.folio_amount}"
  expect(@target_remittance_payment.folio_amount.to_f).not_to eq(@folio_amount)
  expect(@target_remittance_payment.amount.to_f).to eq(@amount)
end
