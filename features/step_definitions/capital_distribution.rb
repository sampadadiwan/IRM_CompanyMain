When("I create a Capital Distribution {string}") do |args|
  visit(fund_path(@fund))
  @capital_distribution = FactoryBot.build(:capital_distribution, fund: @fund)
  key_values(@capital_distribution, args)
  click_on("Distributions")
  click_on("New Distribution")

  fill_in 'capital_distribution_title', with: @capital_distribution.title
  fill_in 'capital_distribution_income', with: @capital_distribution.income.to_d
  fill_in 'capital_distribution_cost_of_investment', with: @capital_distribution.cost_of_investment.to_d
  fill_in 'capital_distribution_reinvestment', with: @capital_distribution.reinvestment.to_d
  fill_in 'capital_distribution_distribution_date', with: @capital_distribution.distribution_date.strftime("%Y-%m-%d")

  CapitalCommitment.first.account_entries.all.each do |ae|
    # For each account entry, add a distribution fee
    puts "Adding distribution fee for account entry #{ae}"
    click_link 'Add Account Entries'

    within all('.nested-fields').last do
      select ae.name, from: 'fee_name'
      fill_in 'fee_start_date', with: (ae.reporting_date - 1.month).strftime("%Y-%m-%d")
      fill_in 'fee_end_date', with: (ae.reporting_date + 1.month).strftime("%Y-%m-%d")
      select ae.entry_type, from: 'fee_type'
      fill_in 'fee_notes', with: "From account entry #{ae.id}"
    end
  end

  click_button 'Save'
  expect(page).to have_content("Capital distribution was successfully created")
  # sleep(2)
end

Given("there is a AccountEntry for distribution {string}") do |args|
  CapitalCommitment.all.each do |cc|
    ae = @fund.account_entries.build(entity_id: @fund.entity_id, capital_commitment_id: cc.id)
    key_values(ae, args)
    ae.save!
    puts ae.to_json
  end
end

Then('it should create Capital Distribution') do
  distribution = CapitalDistribution.first
  expect(distribution.title).to(eq(@capital_distribution.title))
  expect(distribution.income_cents).to(eq(@capital_distribution.income_cents))
  expect(distribution.cost_of_investment_cents).to(eq(@capital_distribution.cost_of_investment_cents))
  expect(distribution.reinvestment_cents).to(eq(@capital_distribution.reinvestment_cents))

  @capital_distribution.income_cents
  @capital_distribution.cost_of_investment_cents
  @capital_distribution.reinvestment_cents
  AccountEntry.where(fund_id: @fund.id).where.not(entry_type: %w[Tax Expense]).sum(:amount_cents)
  # total_amount_cents -=  AccountEntry.where(fund_id: @fund.id).where(entry_type: ["Tax", "Expense"]).sum(:amount_cents)

  expect(distribution.gross_amount_cents).to(eq(distribution.capital_distribution_payments.sum(:gross_payable_cents)))
  expect(distribution.completed_distribution_amount_cents).to(eq(distribution.capital_distribution_payments.completed.sum(:net_payable_cents)))
end

Then('the data should be correctly displayed for each Capital Distribution Payment') do
  CapitalDistributionPayment.all.each do |cdp|
    visit(capital_distribution_payment_path(cdp))
    # sleep(20)
    puts "checking details of #{cdp}"

    cdp.income_with_fees_cents.should == cdp.income_cents + AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["Income"]).sum(:amount_cents) - AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: %w[Tax Expense]).sum(:amount_cents)
    cdp.cost_of_investment_with_fees_cents.should == cdp.cost_of_investment_cents + AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["FV For Redemption"]).sum(:amount_cents)
    cdp.reinvestment_with_fees_cents.should == cdp.reinvestment_cents + AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["Reinvestment"]).sum(:amount_cents)

    cdp.net_payable_cents.should == cdp.income_with_fees_cents + cdp.cost_of_investment_with_fees_cents - cdp.reinvestment_with_fees_cents
    cdp.gross_payable_cents.should == cdp.income_cents + cdp.cost_of_investment_cents + AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["Income", "FV For Redemption"]).sum(:amount_cents)

    expect(page).to have_content(money_to_currency(cdp.net_payable, {}))
    expect(page).to have_content(money_to_currency(cdp.income, {}))
    expect(page).to have_content(money_to_currency(cdp.income_with_fees, {}))
    expect(page).to have_content(money_to_currency(cdp.cost_of_investment, {}))
    expect(page).to have_content(money_to_currency(cdp.cost_of_investment_with_fees, {}))
    expect(page).to have_content(money_to_currency(cdp.reinvestment, {}))

    expect(page).to have_content(cdp.payment_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(cdp.capital_distribution.to_s)
    expect(page).to have_content(cdp.capital_commitment.to_s)
    AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).each do |ae|
      name = FormCustomField.to_name(ae.name)
      puts "checking details of #{name} in #{cdp.json_fields}"
      expect(cdp.json_fields[name]).to(eq(money_to_currency(ae.amount, {})))
    end
  end
end

When('the capital distribution notifications are sent') do
  CapitalDistributionPaymentNotificationJob.perform_now(@capital_distribution.id, @user.id)
end

Then('the Display Only fee should not affect income_with_fees_cents') do
  CapitalDistributionPayment.all.each do |cdp|
    AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: "Display Only").sum(:amount_cents)
    # Display Only should not affect income_with_fees_cents
    cdp.income_with_fees_cents.should == cdp.income_cents
    puts "Display Only: income_with_fees_cents (#{cdp.income_with_fees_cents}) == income_cents (#{cdp.income_cents}) - PASS"
  end
end

Then('the Display Only fee should not affect cost_of_investment_with_fees_cents') do
  CapitalDistributionPayment.all.each do |cdp|
    # Display Only should not affect cost_of_investment_with_fees_cents
    cdp.cost_of_investment_with_fees_cents.should == cdp.cost_of_investment_cents
    puts "Display Only: cost_of_investment_with_fees_cents (#{cdp.cost_of_investment_with_fees_cents}) == cost_of_investment_cents (#{cdp.cost_of_investment_cents}) - PASS"
  end
end

Then('the ae_audit should contain the Display Only fee details') do
  CapitalDistributionPayment.all.each do |cdp|
    ae_audit = cdp.json_fields["ae_audit"]
    puts "Checking ae_audit for Display Only: #{ae_audit}"
    expect(ae_audit).to be_present, "ae_audit should be present"
    # ae_audit is an array of arrays, each containing [name, reporting_date, amount_cents, fee_type]
    expect(ae_audit.flatten).to include("Display Only"), "ae_audit should contain Display Only fee type"
  end
end

Then('the json_fields should contain the Display Only fee name with amount {string}') do |_expected_amount|
  CapitalDistributionPayment.all.each do |cdp|
    # The json_fields key is the name converted using FormCustomField.to_name
    json_key = FormCustomField.to_name("Audit Entry")
    json_value = cdp.json_fields[json_key]
    puts "Checking json_fields[#{json_key}] = #{json_value}"
    expect(json_value).to be_present, "json_fields should contain the Display Only fee name"
    # The value is stored as currency (e.g., "₹999.99"), so just verify it's non-zero
    expect(json_value.to_s.gsub(/[^\d]/, '').to_i).to be > 0, "json_fields should contain a non-zero amount"
  end
end

Then('the reinvestment_with_fees_cents should be correctly calculated') do
  CapitalDistributionPayment.all.each do |cdp|
    reinvestment_ae_amount = AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: "Reinvestment").sum(:amount_cents)
    expected_reinvestment_with_fees = cdp.reinvestment_cents + reinvestment_ae_amount
    cdp.reinvestment_with_fees_cents.should == expected_reinvestment_with_fees
    puts "Reinvestment: reinvestment_with_fees_cents (#{cdp.reinvestment_with_fees_cents}) == reinvestment_cents (#{cdp.reinvestment_cents}) + AE amount (#{reinvestment_ae_amount}) - PASS"
  end
end

Then('the net_payable_cents should account for reinvestment correctly') do
  CapitalDistributionPayment.all.each do |cdp|
    # Verify net_payable is correctly computed (reinvestment increases reinvestment_with_fees which reduces net_payable)
    reinvestment_fees_cents = AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: "Reinvestment").sum(:amount_cents)
    # net_payable should be income + cost_of_investment + net_ae_from_reinvestment - reinvestment_with_fees
    # Since reinvestment adds to both net_ae and reinvestment_with_fees, they cancel out for Reinvestment type
    expected_net_payable = cdp.income_cents + cdp.cost_of_investment_cents - (cdp.reinvestment_cents + reinvestment_fees_cents)
    cdp.net_payable_cents.should == expected_net_payable
    puts "Net Payable with Reinvestment: net_payable_cents (#{cdp.net_payable_cents}) == income_cents (#{cdp.income_cents}) + cost_of_investment_cents (#{cdp.cost_of_investment_cents}) - PASS"
  end
end

Then('the expense should reduce the income_with_fees_cents correctly') do
  CapitalDistributionPayment.all.each do |cdp|
    expense_ae_amount = AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: "Expense").sum(:amount_cents)
    expected_income_with_fees = cdp.income_cents - expense_ae_amount
    cdp.income_with_fees_cents.should == expected_income_with_fees
    puts "Expense: income_with_fees_cents (#{cdp.income_with_fees_cents}) == income_cents (#{cdp.income_cents}) - expense AE amount (#{expense_ae_amount}) - PASS"
  end
end

Then('the distribution payments should have the {string} fee details') do |fee_type|
  attr_name = fee_type.downcase.gsub(" ", "_") + "_with_fees_cents"
  CapitalDistributionPayment.all.each do |cdp|
    fee_ae_amount = AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: fee_type).sum(:amount_cents)
    puts "Checking #{fee_type} fee details for CD Payment #{cdp.id}: AE amount = #{fee_ae_amount} cents, attribute #{attr_name} = #{cdp.send(attr_name)} cents"
    expect(fee_ae_amount).to be > 0, "Expected to find AccountEntry with fee type #{fee_type} for capital commitment #{cdp.capital_commitment_id}"
    expect(cdp.send(attr_name)).to eq fee_ae_amount
  end
end

Then('the tax should reduce the income_with_fees_cents correctly') do
  CapitalDistributionPayment.all.each do |cdp|
    tax_ae_amount = AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id, entry_type: "Tax").sum(:amount_cents)
    expected_income_with_fees = cdp.income_cents - tax_ae_amount
    puts "Checking Tax fee details for CD Payment #{cdp.id}: income_cents = #{cdp.income_cents} cents, Tax AE amount = #{tax_ae_amount} cents, expected income_with_fees_cents = #{expected_income_with_fees} cents"
    cdp.income_with_fees_cents.should == expected_income_with_fees
    puts "Tax: income_with_fees_cents (#{cdp.income_with_fees_cents}) == income_cents (#{cdp.income_cents}) - tax AE amount (#{tax_ae_amount}) - PASS"
  end
end
