  include InvestmentsHelper
  include ActionView::Helpers::SanitizeHelper

  Given('I am at the funds page') do
    visit(funds_url)
  end
  
  When('I create a new fund {string}') do |arg1|
    @fund = FactoryBot.build(:fund)
    key_values(@fund, arg1)

    click_on("New Fund")
    fill_in('fund_name', with: @fund.name)
    # fill_in('fund_details', with: @fund.details)
    find('trix-editor').click.set(@fund.details)
    click_on("Save")
  end
  
  Then('an fund should be created') do
    db_fund = Fund.last
    db_fund.name.should == @fund.name
    strip_tags(db_fund.details) == @fund.details

    @fund = db_fund
  end
  
  Then('I should see the fund details on the details page') do
    expect(page).to have_content(@fund.name)
    expect(page).to have_content(strip_tags(@fund.details))
  end
  
  Then('I should see the fund in all funds page') do
    expect(page).to have_content(@fund.name)
    expect(page).to have_content(money_to_currency @fund.collected_amount)
  end
  

  Given('there is a fund {string} for the entity') do |arg|
    @fund = FactoryBot.build(:fund, entity_id: @user.entity_id)
    key_values(@fund, arg)
    @fund.save
    puts "\n####Fund####\n"
    puts @fund.to_json
  end
  
  Given('the investors are added to the fund') do
    @user.entity.investors.not_holding.not_trust.each do |inv|
        ar = AccessRight.create!( owner: @fund, access_type: "Fund", 
                                 access_to_investor_id: inv.id, entity: @user.entity)


        puts "\n####Granted Access####\n"
        puts ar.to_json                            
    end 
    
  end

  When('I add a capital commitment {string} for investor {string}') do |amount, investor_name|

    visit(fund_url(@fund))
    click_on("Commitments")
    click_on("New Capital Commitment")
    select(investor_name, from: "capital_commitment_investor_id")
    fill_in('capital_commitment_committed_amount', with: amount)

    click_on "Save"

    sleep(1)
  end
  
  Then('the fund total committed amount must be {string}') do |amount|
    @fund.reload
    (@fund.committed_amount_cents / 100).should == amount.to_i
  end
  
  Given('there are capital commitments of {string} from each investor') do |args|
    @fund.investors.each do |inv|
        commitment = FactoryBot.build(:capital_commitment, fund: @fund)
        key_values(commitment, args)
        commitment.save
        puts "\n####CapitalCommitment####\n"
        puts commitment.to_json
    end
  end
  
  When('I create a new capital call {string}') do |args|
    @capital_call = FactoryBot.build(:capital_call, fund: @fund)
    key_values(@capital_call, args)
    
    visit(fund_url(@fund))

    click_on "Capital Calls"
    click_on "New Capital Call"

    fill_in('capital_call_name', with: @capital_call.name)
    fill_in('capital_call_percentage_called', with: @capital_call.percentage_called)
    fill_in('capital_call_due_date', with: @capital_call.due_date)
    
    click_on "Save"
    sleep(1)

  end

  Then('the corresponding remittances should be created') do
    @capital_call = CapitalCall.last
    @capital_call.capital_remittances.each do |remittance|
        cc = @fund.capital_commitments.where(investor_id: remittance.investor_id).first
        (cc.committed_amount * @capital_call.percentage_called / 100.0).should == remittance.due_amount
    end
  end
  
  Then('I should see the remittances') do
    @capital_call.reload

    visit(capital_call_url(@capital_call))
    click_on "Remittances"

    @capital_call.capital_remittances.each do |remittance|
        within("#capital_remittance_#{remittance.id}") do
            expect(page).to have_content(remittance.investor.investor_name)
            within(".verified") do
              expect(page).to have_content(remittance.verified ? "Yes" : "No")
            end
            expect(page).to have_content(remittance.status)
            expect(page).to have_content(money_to_currency remittance.due_amount)
            expect(page).to have_content(money_to_currency remittance.collected_amount)            
        end
    end
  end
  

   Then('I should see the capital call details') do
    expect(page).to have_content(@capital_call.name)
    expect(page).to have_content(@capital_call.percentage_called)
    expect(page).to have_content(@capital_call.due_date.strftime("%d/%m/%Y"))

    @capital_call = CapitalCall.last
  end

  When('I mark the remittances as paid') do

    @capital_call.capital_remittances.each do |remittance|
      visit(capital_call_url(@capital_call))
      click_on "Remittances"
      within("#capital_remittance_#{remittance.id}") do
        click_on "Paid"
      end
      fill_in('capital_remittance_collected_amount', with: remittance.due_amount)
      click_on "Save"
      sleep(1)
    end
  end
  
  When('I mark the remittances as verified') do

    @capital_call.capital_remittances.each do |remittance|
      visit(capital_call_url(@capital_call))
      click_on "Remittances"
      within("#capital_remittance_#{remittance.id}") do
        click_on "Verify"
      end
      sleep(1)
      click_on "Proceed"
      sleep(1)
    end
  end
  
  
  
  