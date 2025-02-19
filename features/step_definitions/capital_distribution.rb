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

  total_amount_cents = @capital_distribution.income_cents + @capital_distribution.cost_of_investment_cents + @capital_distribution.reinvestment_cents

  total_amount_cents +=  AccountEntry.where(fund_id: @fund.id).where.not(entry_type: ["Tax", "Expense"]).sum(:amount_cents)
  # total_amount_cents -=  AccountEntry.where(fund_id: @fund.id).where(entry_type: ["Tax", "Expense"]).sum(:amount_cents)

  expect(distribution.gross_amount_cents).to(eq(distribution.capital_distribution_payments.completed.sum(:gross_payable_cents)))  
end

Then('the data should be correctly displayed for each Capital Distribution Payment') do
  CapitalDistributionPayment.all.each do |cdp|
    visit(capital_distribution_payment_path(cdp))
    # sleep(20)
    puts "checking details of #{cdp}"

    cdp.income_with_fees_cents.should == cdp.income_cents + AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["Income"]).sum(:amount_cents) - AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["Tax", "Expense"]).sum(:amount_cents)
    cdp.cost_of_investment_with_fees_cents.should == cdp.cost_of_investment_cents + AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["FV For Redemption"]).sum(:amount_cents)
    cdp.reinvestment_with_fees_cents.should == cdp.reinvestment_cents + AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["Reinvestment"]).sum(:amount_cents)

    cdp.net_payable_cents.should == cdp.income_with_fees_cents + cdp.cost_of_investment_with_fees_cents - cdp.reinvestment_with_fees_cents
    cdp.gross_payable_cents.should == cdp.income_cents + cdp.cost_of_investment_cents + AccountEntry.where(capital_commitment_id: cdp.capital_commitment_id).where(entry_type: ["Income", "FV For Redemption"]).sum(:amount_cents)

    expect(page).to have_content(money_to_currency cdp.net_payable, {})
    expect(page).to have_content(money_to_currency cdp.income, {})
    expect(page).to have_content(money_to_currency cdp.income_with_fees, {})    
    expect(page).to have_content(money_to_currency cdp.cost_of_investment, {})
    expect(page).to have_content(money_to_currency cdp.cost_of_investment_with_fees, {})
    expect(page).to have_content(money_to_currency cdp.reinvestment, {})    

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
