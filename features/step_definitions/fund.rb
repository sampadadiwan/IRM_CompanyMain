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

  Given('I am {string} employee access to the fund') do |given|
    if given == "given" || given == "yes"
      AccessRight.create(entity_id: @fund.entity_id, owner: @fund, user_id: @user.id)
    end
  end

  Given('another user is {string} investor access to the fund') do |given|
    # Hack to make the tests work without rewriting many steps for another user
    @user = @employee_investor
    if given == "given" || given == "yes"
      AccessRight.create(entity_id: @fund.entity_id, owner: @fund, access_to_investor_id: @investor.id)
      ia = InvestorAccess.create(entity: @investor.entity, investor: @investor, 
        first_name: @user.first_name, last_name: @user.last_name,
        email: @user.email, granter: @user, approved: true )

      puts "\n####Investor Access####\n"
      puts ia.to_json
    end
  end
  
  
  When('I am at the fund details page') do
    visit(fund_url(@fund))
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

    sleep(2)
  end
  
  Then('the fund total committed amount must be {string}') do |amount|
    @fund.reload
    (@fund.committed_amount_cents / 100).should == amount.to_i
  end
  
  Given('there are capital commitments of {string} from each investor') do |args|
    @fund.investors.each do |inv|
        commitment = FactoryBot.build(:capital_commitment, fund: @fund, investor: inv)
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
    sleep(2)

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
    @fund.capital_commitments.count.should == 2
    @capital_call.capital_remittances.count.should == 2

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
      sleep(2)
      click_on "Remittances"      
      within("#capital_remittance_#{remittance.id}") do
        click_on "Paid"
        sleep(1)
      end
      fill_in('capital_remittance_collected_amount', with: remittance.due_amount)
      click_on "Save"
      sleep(1)
    end
  end
  
  When('I mark the remittances as verified') do

    @capital_call.capital_remittances.each do |remittance|
      visit(capital_call_url(@capital_call))
      sleep(2)
      click_on "Remittances"      
      within("#capital_remittance_#{remittance.id}") do
        click_on "Verify"
        sleep(1)
      end
      click_on "Proceed"
      sleep(1)
    end
  end


Then('the capital call collected amount should be {string}') do |arg|
  @capital_call.reload
  @capital_call.collected_amount.should == Money.new(arg.to_i * 100, @capital_call.entity.currency)
end

  
  
Then('user {string} have {string} access to the fund') do |truefalse, accesses|
  accesses.split(",").each do |access|
    puts "##Checking access #{access} on fund #{@fund.name} for #{@user.email} as #{truefalse}"
    Pundit.policy(@user, @fund).send("#{access}?").to_s.should == truefalse
  end
end

Given('the fund has capital commitments from each investor') do
  @entity.investors.each do |inv|
    cc = FactoryBot.create(:capital_commitment, fund: @fund, investor: inv)
    puts "\n####CapitalCommitment####\n"
    puts cc.to_json
  end

  @fund.reload
end

Then('user {string} have {string} access to the capital commitment') do |truefalse, accesses|
  accesses.split(",").each do |access|
    @fund.capital_commitments.includes(:investor).each do |cc|
      puts "##Checking access #{access} on capital_commitment from #{cc.investor.investor_name} for #{@user.email} as #{truefalse}"
      Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
    end
  end
end

Then('user {string} have {string} access to his own capital commitment') do |truefalse, accesses|
  accesses.split(",").each do |access|
    @fund.capital_commitments.includes(:investor).each do |cc|
      puts "##Checking access #{access} on capital_commitment from #{cc.investor.investor_name} for #{@user.email} is #{Pundit.policy(@user, cc).send("#{access}?")}"
      
      if(cc.investor.investor_entity_id == @user.entity_id)
        Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
      else
        Pundit.policy(@user, cc).send("#{access}?").to_s.should == "false"
      end
      
    end
  end
end


Given('the fund has {string} capital call') do |count|
  (1..count.to_i).each do |i|
    cc = FactoryBot.create(:capital_call, fund: @fund)
    puts "\n####CapitalCall####\n"
    puts cc.to_json
  end

  @fund.reload
end

Then('user {string} have {string} access to the capital calls') do |truefalse, accesses|
  puts "##### Checking access to capital calls for funds with rights #{@fund.access_rights.to_json}"
  accesses.split(",").each do |access|
    @fund.capital_calls.each do |cc|
      puts "##Checking access #{access} on capital_call from #{cc.name} for #{@user.email} as #{truefalse}"
      Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
    end
  end
end


Given('the capital calls are approved') do
  @fund.capital_calls.each do |cc|
    cc.approved = true
    cc.approved_by_user = @user
    cc.save
  end
end

Then('user {string} have {string} access to the capital remittances') do |truefalse, accesses|
  puts "##### Checking access to capital remittances for funds with rights #{@fund.access_rights.to_json}"
  accesses.split(",").each do |access|
    @fund.capital_remittances.includes(:investor).each do |cc|
      puts "##Checking access #{access} on capital_remittance from #{cc.investor.investor_name} for #{@user.email} as #{truefalse}"
      Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
    end
  end
end

Then('user {string} have {string} access to his own capital remittances') do |truefalse, accesses|
  puts "##### Checking access to capital remittances for funds with rights #{@fund.access_rights.to_json}"
  accesses.split(",").each do |access|
    @fund.capital_remittances.includes(:investor).each do |cc|
      puts "##Checking access #{access} on capital_remittance from #{cc.investor.investor_name} for #{@user.email} is #{Pundit.policy(@user, cc).send("#{access}?")}"
      if(cc.investor.investor_entity_id == @user.entity_id)
        Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
      else
        Pundit.policy(@user, cc).send("#{access}?").to_s.should == "false"
      end
    end
  end
end


Given('the fund has {string} capital distribution') do |count|
  (1..count.to_i).each do |i|
    cc = FactoryBot.create(:capital_distribution, fund: @fund)
    puts "\n####CapitalDistribution####\n"
    puts cc.to_json
  end

  @fund.reload
end

Then('user {string} have {string} access to the capital distributions') do |truefalse, accesses|
  puts "##### Checking access to capital distributions for funds with rights #{@fund.access_rights.to_json}"
  accesses.split(",").each do |access|
    @fund.capital_distributions.each do |cc|
      puts "##Checking access #{access} on capital_distribution from #{cc.title} for #{@user.email} as #{truefalse}"
      Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
    end
  end
end

Given('the capital distributions are approved') do
  @fund.capital_distributions.each do |cc|
    cc.approved = true
    cc.approved_by_user = @user
    cc.save
  end
end

Then('user {string} have {string} access to the capital distribution payments') do |truefalse, accesses|
    puts "##### Checking access to capital distribution payments for funds with rights #{@fund.access_rights.to_json}"
    accesses.split(",").each do |access|
      @fund.capital_distribution_payments.includes(:investor).each do |cc|
        puts "##Checking access #{access} on capital_distribution_payments from #{cc.investor.investor_name} for #{@user.email} as #{truefalse}"
        Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
      end
    end
end


Then('user {string} have {string} access to his own capital distribution payments') do |truefalse, accesses|
  puts "##### Checking access to capital distribution payments for funds with rights #{@fund.access_rights.to_json}"
  accesses.split(",").each do |access|
    @fund.capital_distribution_payments.includes(:investor).each do |cc|
      puts "##Checking access #{access} on capital_distribution_payments from #{cc.investor.investor_name} for #{@user.email} as #{Pundit.policy(@user, cc).send("#{access}?")}"
      if(cc.investor.investor_entity_id == @user.entity_id)
        Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
      else
        Pundit.policy(@user, cc).send("#{access}?").to_s.should == "false"
      end
    end
  end
end


When('I create a new capital distribution {string}') do |args|
  @capital_distribution = FactoryBot.build(:capital_distribution, fund: @fund)
  key_values(@capital_distribution, args)
  
  visit(fund_url(@fund))

  click_on "Capital Distributions"
  click_on "New Capital Distribution"

  fill_in('capital_distribution_title', with: @capital_distribution.title)
  fill_in('capital_distribution_gross_amount', with: @capital_distribution.gross_amount)
  fill_in('capital_distribution_carry', with: @capital_distribution.carry)
  fill_in('capital_distribution_distribution_date', with: @capital_distribution.distribution_date)
  
  click_on "Save"
  sleep(2)

end

Then('I should see the capital distrbution details') do
  expect(page).to have_content(@capital_distribution.title)
  expect(page).to have_content(money_to_currency(@capital_distribution.gross_amount))
  expect(page).to have_content(money_to_currency(@capital_distribution.carry))
  expect(page).to have_content(money_to_currency(@capital_distribution.net_amount))
  expect(page).to have_content(@capital_distribution.distribution_date.strftime("%d/%m/%Y"))

  @new_capital_distribution = CapitalDistribution.last
  @new_capital_distribution.approved.should == false
  @new_capital_distribution.distribution_amount_cents.should == 0
  @new_capital_distribution.capital_distribution_payments.length.should == 0

  @capital_distribution = @new_capital_distribution
end

Then('when the capital call is approved') do
  @capital_call.approved = true
  @capital_call.approved_by_user = @user
  @capital_call.save
  sleep(1)
  @capital_call.reload
end


Then('when the capital distrbution is approved') do
  @capital_distribution.approved = true
  @capital_distribution.approved_by_user = @user
  @capital_distribution.save
  sleep(1)
  @capital_distribution.reload
end

Then('I should see the capital distrbution payments generated correctly') do
  puts "### payments length = #{@capital_distribution.capital_distribution_payments.length}"
  @capital_distribution.capital_distribution_payments.length.should == @fund.capital_commitments.length
  @fund.capital_commitments.each do |cc|
    cdp = @capital_distribution.capital_distribution_payments.where(investor_id: cc.investor_id).first
    cdp.completed.should == false
    cdp.amount_cents.should == cc.percentage *  @capital_distribution.net_amount_cents / 100
  end
end

Then('I should be able to see the capital distrbution payments') do
  visit(capital_distribution_path(@capital_distribution))
  @capital_distribution.capital_distribution_payments.includes(:investor).each do |p|
    within "#capital_distribution_payment_#{p.id}" do
      expect(page).to have_content(p.investor.investor_name)
      expect(page).to have_content(money_to_currency(p.amount))
      expect(page).to have_content(p.payment_date.strftime("%d/%m/%Y"))
      expect(page).to have_content(p.completed ? "Yes" : "No")
    end
  end
end

Then('when the capital distrbution payments are marked as paid') do
  @capital_distribution.capital_distribution_payments.update(completed: true)
end

Then('the capital distribution must reflect the payments') do
  @capital_distribution.reload
  @capital_distribution.distribution_amount_cents.should == @capital_distribution.capital_distribution_payments.sum(:amount_cents)
end




  