When('I create a Capital Call with percentage of commitment') do
	visit("/funds/1")
	#sleep(0.5)
	find('a.nav-link[href="#capital-calls-tab"]').click
	#sleep(0.2)
	click_on("New Call")
	#sleep(0.2)
	fill_in 'capital_call_name', with: 'Demo call'
	#sleep(1)
	fill_in "capital_call[close_percentages][First Close]", with: "10"
	fill_in "capital_call[close_percentages][Second Close]", with: "20"
  find('input[name="capital_call[call_date]"]').set('2024-09-13')
  find('input[name="capital_call[due_date]"]').set('2024-11-13')
  allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
  click_on('Save')
  expect(page).to have_content("Capital call was successfully")
end

When("I create a Capital Call with upload call basis") do
	allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
	visit("/funds/1")
	#sleep(0.5)
	find('a.nav-link[href="#capital-calls-tab"]').click
	#sleep(0.2)
	click_on("New Call")
	#sleep(0.2)
	fill_in 'capital_call_name', with: 'Upload capital call'
	#sleep(1)
	select 'Upload', from: 'capital_call[call_basis]'
	fill_in 'Series A_price', with: '1'
	click_on('Save')
	expect(page).to have_content("Capital call was successfully")
end

When("I create a Capital Call with investable call basis") do
	visit("/funds/1")
	#sleep(0.5)
	find('a.nav-link[href="#capital-calls-tab"]').click
	#sleep(0.2)
	click_on("New Call")
	#sleep(0.2)
	fill_in 'capital_call_name', with: 'Investable capital call'
	#sleep(1)
	select 'Investable Capital Percentage', from: 'capital_call[call_basis]'
	find('span.select2-selection--multiple').click
	find('ul.select2-results__options', visible: true)
	find('li.select2-results__option', text: 'Second Close').click
	click_on('Save')
	expect(page).to have_content("Capital call was successfully")
end

Given("it should create a Capital Call with given data") do
	capital_call = CapitalCall.last
	expect(capital_call.name).to(eq("Upload capital call"))
	expect(capital_call.call_basis).to(eq("Upload"))
	expect(capital_call.fund_closes).to_not be_present
end

Given("it should create a Investable Capital Call with given data") do
	capital_call = CapitalCall.last
	expect(capital_call.name).to(eq("Investable capital call"))
	expect(capital_call.call_basis).to(eq("Investable Capital Percentage"))
	expect(capital_call.fund_closes).to(eq(["Second Close"]))
end

Given("it should create Capital Remittances according to the close percentage") do
	expect(CapitalRemittance.pluck(:percentage)).to match_array([BigDecimal("10"), BigDecimal("20")])
end

Given('the remittances has some units already allocated') do
  capital_remittance = CapitalRemittance.last
  fund_unit = capital_remittance.fund_units.build(
    fund_id:capital_remittance.capital_commitment.fund_id,
    capital_commitment_id: capital_remittance.capital_commitment.id,
    investor_id: capital_remittance.capital_commitment.investor_id,
    entity_id: capital_remittance.entity_id,
    unit_type: capital_remittance.capital_commitment.unit_type,
    quantity: 10.0,
    price: 50.0,
    premium: 10.0,
    issue_date: Date.today,
    reason: "Initial Allocation"
  )
  fund_unit.save!

  @pending_amount_for_units_allocation, @reason = capital_remittance.pending_amount_for_units_allocation
  puts "Pending amount for units allocation: #{@pending_amount_for_units_allocation}"
  puts "Reason: #{@reason}"
end


Then('it should generate only the remaining units') do
	
	capital_remittance = CapitalRemittance.last
	fund_unit = capital_remittance.fund_units.last
	puts "Fund Unit: #{fund_unit.inspect}"
	expect(fund_unit).to be_present
	expect(fund_unit.amount.cents).to eq(@pending_amount_for_units_allocation)
	expect(fund_unit.reason).to include(@reason)	

	# Ensure that the new fund unit is created
	capital_remittance.fund_units.count.should == 2
end

  
And("error email for fund units already allocated should be sent") do
	current_email = open_email(User.first.email)
	expect(current_email).to have_content("Fund Units already allocated")
end

Given('I delete a remittance with no payments') do
  CapitalRemittance.all.each do |cr|
		if cr.capital_remittance_payments.blank?
			@capital_remittance = cr
			break
		end						
  end
	visit capital_remittance_path(@capital_remittance)
	click_on "Delete"
	click_on "Proceed"
end

Then('the remittance is successfully deleted') do
	expect(page).to have_content("Capital remittance was successfully destroyed")
end

Given('I delete a remittance having payments with allocated units') do
	CapitalRemittance.all.each do |cr|
		if cr.capital_remittance_payments.present?
			 cr.capital_remittance_payments.each do |payment|
				 if payment.units_already_allocated?
					 puts "Found a remittance with allocated units: #{cr.id}"
					 @capital_remittance = cr
					 break
				 end
			 end
		end
	end
	@user = User.first
	@user.add_role(:company_admin)
	visit capital_remittance_path(@capital_remittance)
	click_on "Delete"
	click_on "Proceed"
end

Then('I get the error {string}') do |string|
	expect(page).to have_content(string)
end

