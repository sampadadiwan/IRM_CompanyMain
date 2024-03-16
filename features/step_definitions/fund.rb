  include CurrencyHelper
  include ActionView::Helpers::SanitizeHelper

  Given('I am at the funds page') do
    visit(funds_url)
  end

  When('I create a new fund {string}') do |arg1|
    @fund = FactoryBot.build(:fund)
    key_values(@fund, arg1)

    click_on("New Fund")
    fill_in('fund_name', with: @fund.name)
    select(@fund.currency, from: "fund_currency")
    # fill_in('fund_currency', with: @fund.currency)
    fill_in('fund_unit_types', with: @fund.unit_types) if @fund.entity.permissions.enable_units?
    # fill_in('fund_details', with: @fund.details)
    find('trix-editor').click.set(@fund.details)
    click_on("Next")
    click_on("Next")
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
      @access_right = AccessRight.create(entity_id: @fund.entity_id, owner: @fund, user_id: @user.id)
    end
  end

  Given('another user is {string} investor access to the fund') do |given|
    # Hack to make the tests work without rewriting many steps for another user
    @user = @employee_investor
    if given == "given" || given == "yes"
      @access_right = AccessRight.create!(entity_id: @fund.entity_id, owner: @fund, access_to_investor_id: @investor.id,
                                          metadata: "Investor")
      ia = InvestorAccess.create!(entity: @investor.entity, investor: @investor,
        first_name: @user.first_name, last_name: @user.last_name,
        email: @user.email, granter: @user, approved: true )

      puts "\n####Investor Access####\n"
      puts ia.to_json
    end

    @fund.reload
  end

  Given('another user is {string} investor advisor access to the fund') do |given|
    @user = @employee_investor

    if given == "given" || given == "yes"
      @entity.investors.each do |inv|
        if inv.investor_entity.entity_type != "Investor Advisor"
          # Create the Investor Advisor
          investor_advisor = InvestorAdvisor.create!(entity_id: inv.investor_entity_id, email: @user.email)
          investor_advisor.permissions.set(:enable_funds)
          investor_advisor.save

          puts "\n####Investor Advisor####\n"
          puts investor_advisor.to_json

          # Switch the IA to the entity
          investor_advisor.switch(@user)

          # Create the Access Right
          @access_right = AccessRight.create!(entity_id: inv.investor_entity_id, owner: @fund, user_id: @user.id, metadata: "Investor Advisor")

          puts "\n####Access Right####\n"
          puts @access_right.to_json

          ia = InvestorAccess.create(entity: inv.entity, investor: inv,
          first_name: @user.first_name, last_name: @user.last_name,
          email: @user.email, granter: nil, approved: true )

          puts "\n####Investor Access####\n"
          puts ia.to_json

        end
      end

    end
  end

  Given('another user is {string} fund advisor access to the fund') do |given|
    @user = @employee_investor

    if given == "given" || given == "yes"

          # Create the Investor Advisor
          investor_advisor = InvestorAdvisor.create!(entity_id: @entity.id, email: @user.email)
          investor_advisor.permissions.set(:enable_funds)
          investor_advisor.save

          puts "\n####Investor Advisor####\n"
          puts investor_advisor.to_json

          # Switch the IA to the entity
          investor_advisor.switch(@user)

          # Create the Access Right
          @access_right = AccessRight.create!(entity_id: @entity.id, owner: @fund, user_id: @user.id, metadata: "Investor Advisor")
          @access_right.permissions.set(:create)
          @access_right.permissions.set(:read)
          # @access_right.permissions.set(:update)
          # @access_right.permissions.set(:destroy)
          @access_right.save


          puts "\n####Access Right####\n"
          ap @access_right

    end
  end



  Given('the access right has access {string}') do |crud|
    puts AccessRight.all.to_json
    if @access_right
      crud.split(",").each do |p|
        @access_right.permissions.set(p.to_sym)
      end
      @access_right.save!
      puts "####### AccessRight #######\n"
      puts @access_right.to_json
    end
  end



  When('I am at the fund details page') do
    visit(fund_url(@fund))
  end


  Then('I should see the fund details on the details page') do
    find(".show_details_link").click
    expect(page).to have_content(@fund.name)
    expect(page).to have_content(@fund.unit_types) if @fund.unit_types.present?
    expect(page).to have_content(strip_tags(@fund.details))
  end

  Then('I should see the fund in all funds page') do
    visit(funds_path)
    expect(page).to have_content(@fund.name)
    # expect(page).to have_content(money_to_currency @fund.collected_amount)
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
        ar = AccessRight.create( owner: @fund, access_type: "Fund", metadata: "Investor",
                                 access_to_investor_id: inv.id, entity: @user.entity)


        puts "\n####Granted Access####\n"
        puts ar.to_json
    end

  end

  When('I add a capital commitment {string} for investor {string}') do |amount, investor_name|
    @new_capital_commitment = FactoryBot.build(:capital_commitment, investor_name: investor_name, folio_committed_amount_cents: (amount.to_d * 100), fund: @fund)
    @new_capital_commitment.fund_close ||= "First Close"

    visit(fund_url(@fund))
    click_on("Commitments")
    click_on("New Commitment")
    select(@new_capital_commitment.investor_name, from: "capital_commitment_investor_id")
    fill_in('capital_commitment_folio_committed_amount', with: @new_capital_commitment.folio_committed_amount)
    if @fund.capital_commitments.count > 0
      select(@new_capital_commitment.fund_close, from: "capital_commitment_fund_close")
    else
      fill_in('capital_commitment_fund_close', with: @new_capital_commitment.fund_close)
    end
    fill_in('capital_commitment_folio_id', with: rand(10**4))
    fill_in('capital_commitment_commitment_date', with: @new_capital_commitment.commitment_date)
    select(@new_capital_commitment.folio_currency, from: "capital_commitment_folio_currency")

    if @fund.entity.permissions.enable_units?
      unit_types = @fund.unit_types.split(",").map{|x| x.strip}
      @new_capital_commitment.unit_type = unit_types[rand(unit_types.length)]
      select(@new_capital_commitment.unit_type, from: 'capital_commitment_unit_type')
    end

    click_on "Save"

    sleep(2)
  end

  Then('I should see the capital commitment details') do
    find(".show_details_link").click

    @capital_commitment = CapitalCommitment.last
    @capital_commitment.investor_name.should == @new_capital_commitment.investor_name
    @capital_commitment.unit_type.should == @new_capital_commitment.unit_type
    @capital_commitment.folio_committed_amount_cents.should == @new_capital_commitment.folio_committed_amount_cents

    expect(page).to have_content(@capital_commitment.investor_name)
    expect(page).to have_content(@capital_commitment.entity.name)
    expect(page).to have_content(@capital_commitment.fund_close)
    expect(page).to have_content(money_to_currency @capital_commitment.folio_committed_amount, {})
    expect(page).to have_content(money_to_currency @capital_commitment.committed_amount, {})
    expect(page).to have_content(@capital_commitment.fund.name)
    expect(page).to have_content(@capital_commitment.unit_type) if @fund.entity.permissions.enable_units?
  end

  Then('the fund total committed amount must be {string}') do |amount|
    @fund.reload
    (@fund.committed_amount_cents / 100).should == amount.to_i
  end

  Given('there are capital commitments of {string} from each investor') do |args|
    @fund.investors.each do |inv|
        commitment = FactoryBot.build(:capital_commitment, fund: @fund, investor: inv)
        key_values(commitment, args)
        CapitalCommitmentCreate.call(capital_commitment: commitment)
        puts "\n####CapitalCommitment####\n"
        puts commitment.to_json
    end
  end

  Given('there is a capital commitment of {string} for the last investor') do |args|
    @fund.reload
    inv = Investor.last
    @capital_commitment = FactoryBot.build(:capital_commitment, fund: @fund, investor: inv)
    key_values(@capital_commitment, args)
    result = CapitalCommitmentCreate.call(capital_commitment: @capital_commitment)
    puts "\n####CapitalCommitment####\n"
    puts @capital_commitment.to_json
  end

  Given('there is a capital call {string}') do |arg|
    @capital_call = FactoryBot.build(:capital_call, fund: @fund, entity: @fund.entity)
    key_values(@capital_call, arg)
    CapitalCallCreate.call(capital_call: @capital_call)
    puts "\n####CapitalCall####\n"
    puts @capital_call.to_json
  end


  When('I create a new capital call {string}') do |args|
    @capital_call = FactoryBot.build(:capital_call, fund: @fund)
    key_values(@capital_call, args)
    @capital_call.setup_defaults

    puts @capital_call.to_json

    visit(fund_url(@fund))

    click_on "Calls"
    click_on "New Call"

    fill_in('capital_call_name', with: @capital_call.name)

    fill_in('capital_call_due_date', with: @capital_call.due_date)
    select(@capital_call.fund_closes[0], from: 'capital_call_fund_closes')
    select(@capital_call.call_basis, from: 'capital_call_call_basis')

    if @capital_call.call_basis == "Percentage of Commitment"
      fill_in('capital_call_percentage_called', with: @capital_call.percentage_called)
    elsif @capital_call.call_basis != "Upload"
        fill_in('capital_call_amount_to_be_called', with: @capital_call.amount_to_be_called)
    end

    if @fund.entity.permissions.enable_units?
      @fund.unit_types.split(",").each do |unit_type|
        unit_type = unit_type.strip
        fill_in("#{unit_type}_price", with: @capital_call.unit_prices[unit_type]["price"])
        fill_in("#{unit_type}_premium", with: @capital_call.unit_prices[unit_type]["premium"])
      end
    end

    if @capital_call.call_basis == "Amount allocated on Investable Capital"
      @capital_call.fee_account_entry_names.each_with_index do |fee_name, idx|
        click_on "Add Fees"
        sleep(1)
        within all(".nested-fields").last do
          select(fee_name, from: "fee_name")
          fill_in("fee_start_date", with: Time.zone.today - 10.years)
          fill_in("fee_end_date", with: Time.zone.today)
          select(CapitalCall::FEE_TYPES[0], from: "call_fee_types")
        end
      end
    end

    click_on "Save"
    sleep(2)

  end

  Then('the no remittances should be created') do
    @capital_call = CapitalCall.last
    @capital_call.capital_remittances.count.should == 0
  end

  Then('the corresponding remittances should be created') do

    @capital_call = CapitalCall.last

    if @capital_call.call_basis != "Upload"
      @capital_call.capital_remittances.count.should == @fund.capital_commitments.pool.count
    end

    @capital_call.capital_remittances.each_with_index do |remittance, idx|
        ap remittance
        cc = remittance.capital_commitment
        if @capital_call.call_basis == "Amount allocated on Investable Capital"
          ((@capital_call.amount_to_be_called * remittance.percentage / 100.0) + remittance.capital_fee - remittance.collected_amount).should == remittance.due_amount
        elsif @capital_call.call_basis == "Percentage of Commitment"
          ((cc.committed_amount * @capital_call.percentage_called / 100.0) + remittance.capital_fee - remittance.collected_amount).should == remittance.due_amount
        elsif @capital_call.call_basis == "Upload"
          file = File.open("./public/sample_uploads/capital_remittances.xlsx", "r")
          data = Roo::Spreadsheet.open(file.path) # open spreadsheet
          headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row
          row = data.row(idx+2)
          # create hash from headers and cells
          user_data = [headers, row].transpose.to_h

          puts "Checking import of #{user_data}"
          remittance.investor.investor_name.should == user_data["Investor"].strip
          remittance.fund.name.should == user_data["Fund"]
          remittance.capital_call.name.should == user_data["Capital Call"]
          remittance.call_amount_cents.should == user_data["Call Amount (Inclusive Of Capital Fees)"].to_f * 100
          remittance.capital_fee_cents.should == user_data["Capital Fees"].to_f * 100
          remittance.other_fee_cents.should == user_data["Other Fees"].to_f * 100
          remittance.collected_amount_cents.should == user_data["Collected Amount"].to_f * 100
          remittance.status.should == "Pending"
          remittance.verified.should == (user_data["Verified"] == "Yes")
        end

        # Check the fees
        if @capital_call.call_fees.present?
          @capital_call.call_fees.each do |fee|
            remittance.capital_fee_cents.should > 0
            # remittance.other_fee_cents.should > 0
          end
        end
    end
  end

  Then('I should see the remittances') do
    @capital_call.reload
    # @fund.capital_commitments.count.should == @fund.investors.count
    @capital_call.capital_remittances.count.should == @fund.capital_commitments.pool.count

    visit(capital_call_url(@capital_call))
    sleep(2)
    click_on "Remittances"

    @capital_call.capital_remittances.each do |remittance|
        within("#capital_remittance_#{remittance.id}") do
            expect(page).to have_content(remittance.investor.investor_name)
            expect(page).to have_content(remittance.verified ? "Yes" : "No")
            expect(page).to have_content(remittance.status)
            expect(page).to have_content(money_to_currency remittance.due_amount)
            expect(page).to have_content(money_to_currency remittance.collected_amount)
        end
    end
  end


   Then('I should see the capital call details') do
    find(".show_details_link").click
    expect(page).to have_content(@capital_call.name)
    expect(page).to have_content(@capital_call.percentage_called) if  @capital_call.call_basis == "Percentage of Commitment"
    expect(page).to have_content(money_to_currency @capital_call.amount_to_be_called) if  @capital_call.amount_to_be_called_cents > 0

    expect(page).to have_content(@capital_call.due_date.strftime("%d/%m/%Y"))

    @capital_call = CapitalCall.last
  end

  When('I mark the remittances as paid') do

    @capital_call.capital_remittances.each do |remittance|
      visit(capital_remittance_url(remittance))
      click_on "New Payment"
      fill_in('capital_remittance_payment_folio_amount', with: remittance.due_amount)
      click_on "Save"
      sleep(2)
    end
  end

  When('I mark the remittances as verified') do

    @capital_call.capital_remittances.each do |remittance|
      visit(capital_call_url(@capital_call))
      sleep(1)
      click_on "Remittances"
      sleep(1)
      within("#capital_remittance_#{remittance.id}") do
        click_on "Actions"
        click_on "Verify"
        sleep(1)
      end
      click_on "Proceed"
      sleep(1)
    end
  end


Then('the capital call collected amount should be {string}') do |arg|
  sleep(1)
  @capital_call.reload
  @capital_call.collected_amount.should == Money.new(arg.to_i * 100, @capital_call.fund.currency)
  @capital_call.fund.collected_amount.should == Money.new(arg.to_i * 100, @capital_call.fund.currency)
end



Then('user {string} have {string} access to the fund') do |truefalse, accesses|
  accesses.split(",").each do |access|
    puts "##Checking access #{access} on fund #{@fund.name} for #{@user.email} as #{truefalse}"
    Pundit.policy(@user, @fund).send("#{access}?").to_s.should == truefalse
  end
end

Given('the fund has capital commitments from each investor') do
  @entity.investors.each do |inv|
    if inv.investor_entity.entity_type != "Investor Advisor" # IAs cannot have commitments
      cc = FactoryBot.create(:capital_commitment, fund: @fund, investor: inv)
      puts "\n####CapitalCommitment####\n"
      puts cc.to_json
    end
  end

  @fund.reload
end

Then('user {string} have {string} access to the capital commitment') do |truefalse, accesses|
  @fund.reload
  puts @fund.access_rights.to_json
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
      elsif(@user.investor_advisor?)
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
      elsif(@user.investor_advisor?)
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
  puts "##### Checking access to capital distributions for funds with rights #{@fund.reload.access_rights.to_json}"
  accesses.split(",").each do |access|
    @fund.capital_distributions.each do |cc|
      puts "##Checking access #{access} on capital_distribution from #{cc.title} for #{@user.email} as #{truefalse}"
      Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
    end
  end
end

Then('user {string} have {string} access to his own fund') do |truefalse, accesses|

  truefalse = "true" if truefalse == "yes"
  truefalse = "false" if truefalse == "no"

  puts "##### Checking #{ap @user} with roles #{ap @user.roles} access to funds with rights #{ap @fund.access_rights}"
  accesses.split(",").each do |access|
    acc = Pundit.policy(@user, @fund).send("#{access}?")
    acc.to_s.should == truefalse
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
      elsif(@user.investor_advisor?)
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

  click_on "Distributions"
  sleep(1)
  click_on "New Distribution"

  fill_in('capital_distribution_title', with: @capital_distribution.title)
  fill_in('capital_distribution_gross_amount', with: @capital_distribution.gross_amount)
  fill_in('capital_distribution_cost_of_investment', with: @capital_distribution.cost_of_investment)
  fill_in('capital_distribution_reinvestment', with: @capital_distribution.reinvestment)
  fill_in('capital_distribution_distribution_date', with: @capital_distribution.distribution_date)

  click_on "Save"
  sleep(2)

end

Then('I should see the capital distrbution details') do
  find(".show_details_link").click

  expect(page).to have_content(@capital_distribution.title)
  expect(page).to have_content(money_to_currency(@capital_distribution.gross_amount))
  expect(page).to have_content(money_to_currency(@capital_distribution.reinvestment))
  expect(page).to have_content(money_to_currency(@capital_distribution.net_amount))
  expect(page).to have_content(@capital_distribution.distribution_date.strftime("%d/%m/%Y"))

  @new_capital_distribution = CapitalDistribution.last
  @new_capital_distribution.approved.should == false
  @new_capital_distribution.distribution_amount_cents.should == 0
  # @new_capital_distribution.capital_distribution_payments.length.should == 0

  @capital_distribution = @new_capital_distribution
end

Then('when the capital call is approved') do
  @capital_call.approved = true
  @capital_call.approved_by_user = @user
  CapitalCallUpdate.call(capital_call: @capital_call)
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
  visit(capital_distribution_path(@capital_distribution, tab: "payments-tab"))
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
  @capital_distribution.fund.distribution_amount_cents.should == @capital_distribution.capital_distribution_payments.sum(:amount_cents)
end

Then('the investors must receive email with subject {string}') do |subject|
  sleep(2)
  Investor.all.each do |inv|
    if inv.emails.present?
      inv.emails.each do |email|
        puts "# checking email #{subject} sent for #{email} for investor #{inv}"
        open_email(email)

        @custom_notification ||= nil
        if @custom_notification.present?
          expect(current_email.subject).to include @custom_notification.subject
          expect(current_email.body).to include @custom_notification.body
        else
          expect(current_email.subject).to include subject
        end

        @cc_email ||= nil
        if @cc_email
          puts " Checking cc email #{@cc_email} for #{email}"
          expect(current_email.cc).to include @cc_email
        end
      end
    end
  end
end


Given('Given I upload {string} file for {string} of the fund') do |file, tab|
  
  @import_file = file
  visit(fund_path(@fund))
  click_on(tab)
  sleep(1)
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  sleep(2)
  click_on("Save")
  sleep(3)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
  # ImportUpload.last.failed_row_count.should == 0

end

Then('Given I upload {string} file for Call remittances of the fund') do |file|
  visit(capital_call_path(@capital_call))
  click_on("Remittances")
  sleep(2)
  click_on("Upload / Download")
  click_on("Upload Remittances")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/capital_remittances.xlsx"), make_visible: true)
  sleep(2)
  click_on("Save")
  sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
  ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} capital commitments created') do |count|
  @fund.capital_commitments.count.should == count.to_i
end

Then('the capital commitments must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  capital_commitments = @fund.capital_commitments.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    cc = capital_commitments[idx-1]
    puts "Checking import of #{cc.investor.investor_name}"
    cc.investor.investor_name.should == user_data["Investor"].strip
    cc.fund.name.should == user_data["Fund"]
    cc.commitment_type.should == user_data["Type"]
    cc.commitment_date.should == Date.parse(user_data["Commitment Date"].to_s)
    cc.folio_currency.should == user_data["Folio Currency"]
    cc.folio_committed_amount_cents.should == user_data["Committed Amount"].to_i * 100
    cc.folio_id.should == user_data["Folio No"].to_s
    cc.esign_emails.should == user_data["Investor Signatory Emails"]
    cc.import_upload_id.should == ImportUpload.last.id
    exchange_rate = cc.get_exchange_rate(cc.folio_currency, cc.fund.currency, cc.commitment_date)
    puts "Using exchange_rate #{exchange_rate}"
    committed = cc.foreign_currency? ? (cc.folio_committed_amount_cents * exchange_rate.rate) : cc.folio_committed_amount_cents
    cc.committed_amount_cents.should == committed
  end
end


Then('There should be {string} capital calls created') do |count|
  @fund.capital_calls.count.should == count.to_i
end

Then('the capital calls must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  capital_calls = @fund.capital_calls.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    cc = capital_calls[idx-1]
    puts "Checking import of #{cc.name}"
    cc.name.should == user_data["Name"].strip
    cc.fund.name.should == user_data["Fund"]
    cc.percentage_called.should == user_data["Percentage Called"].to_d
    cc.due_date.should == user_data["Due Date"]
    cc.import_upload_id.should == ImportUpload.last.id
  end
end


Then('There should be {string} capital distributions created') do |count|
  @fund.capital_distributions.count.should == count.to_i
end

Then('the capital distributions must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  capital_distributions = @fund.capital_distributions.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    cc = capital_distributions[idx-1]
    puts "Checking import of #{cc.title}"
    cc.title.should == user_data["Title"].strip
    cc.fund.name.should == user_data["Fund"]
    cc.gross_amount_cents.should == user_data["Gross"].to_i * 100
    cc.reinvestment_cents.should == user_data["Reinvestment"].to_i * 100
    cc.distribution_date.should == user_data["Date"]
    cc.import_upload_id.should == ImportUpload.last.id
  end
end

Then('the capital commitments must have the percentages updated') do
  CapitalCommitment.where(percentage: 0).count.should == 0
end

Then('the fund must have the counter caches updated') do
  
  @fund.reload
  @fund.collected_amount_cents.should == CapitalCommitment.pool.sum(:collected_amount_cents)
  @fund.committed_amount_cents.should == CapitalCommitment.pool.sum(:committed_amount_cents)
  @fund.co_invest_collected_amount_cents.should == CapitalCommitment.co_invest.sum(:collected_amount_cents)
  @fund.co_invest_committed_amount_cents.should == CapitalCommitment.co_invest.sum(:committed_amount_cents)
end


Then('the remittances are generated for the capital calls') do
  Fund.all.each do |fund|
    fund.capital_calls.each do |cc|
      
      commitments = cc.Pool? ? fund.capital_commitments.pool : fund.capital_commitments.co_invest
      puts "Checking remittances for #{cc.name} #{commitments.count} #{cc.capital_remittances.count}"
      cc.capital_remittances.count.should == commitments.count
      cc.capital_remittances.sum(:call_amount_cents).should == cc.call_amount_cents
      cc.capital_remittances.verified.sum(:collected_amount_cents).should == cc.collected_amount_cents
    end
  end
end

Then('the payments are generated for the capital distrbutions') do
  Fund.all.each do |fund|
    fund.capital_distributions.each do |cc|
      # puts cc.capital_distribution_payments.to_json
      capital_distribution_payments_count = cc.Pool? ? fund.capital_commitments.pool.count : 1 # There is only one commitment for each co_invest
      cc.capital_distribution_payments.count.should == capital_distribution_payments_count
      cc.capital_distribution_payments.sum(:amount_cents).round(0).should == cc.net_amount_cents.round(0)
    end
  end
end


Then('the capital commitments are updated with remittance numbers') do
  CapitalCommitment.all.each do |cc|
    cc.reload
    cc.call_amount_cents.should == cc.capital_remittances.sum(:call_amount_cents)
    cc.collected_amount_cents.should == cc.capital_remittances.verified.sum(:collected_amount_cents)
    cc.folio_collected_amount_cents.should == cc.capital_remittances.verified.sum(:folio_collected_amount_cents)
    cc.folio_call_amount_cents.should == cc.capital_remittances.sum(:folio_call_amount_cents)
  end
end

Then('the funds are updated with remittance numbers') do
  Fund.all.each do |f|
    f.reload
    f.call_amount_cents.should == f.capital_remittances.pool.sum(:call_amount_cents)
    f.collected_amount_cents.should == f.capital_remittances.pool.verified.sum(:collected_amount_cents)
    f.co_invest_call_amount_cents.should == f.capital_remittances.co_invest.sum(:call_amount_cents)
    f.co_invest_collected_amount_cents.should == f.capital_remittances.co_invest.verified.sum(:collected_amount_cents)
  end
end


Then('if the last remittance payment is deleted') do
  CapitalRemittancePayment.last&.destroy
end

Then('if the first remittance is deleted') do
  CapitalRemittance.first&.destroy
end


Given('my firm is an investor in the fund') do
  @investor = FactoryBot.create(:investor, entity: @fund.entity, investor_entity: @user.entity)
  puts "\n####Fund Investor####\n"
  puts @investor.to_json

  ar = AccessRight.create!( owner: @fund, access_type: "Fund",
      access_to_investor_id: @investor.id, entity: @fund.entity)


  ia = InvestorAccess.create!(entity: @investor.entity, investor: @investor,
        first_name: @user.first_name, last_name: @user.last_name,
        email: @user.email, granter: @user, approved: true )

  puts "\n####Granted Access####\n"
  puts ar.to_json

  @fund.reload
end


Then('I should be able to see my capital commitments') do
  click_on("Commitments")
  within("#capital_commitments") do
    CapitalCommitment.all.each do |cc|

      puts "checking capital commitment for #{cc.investor.investor_name} against #{@investor.investor_name}"

      if cc.investor_id == @investor.id
        expect(page).to have_content(@investor.investor_name) if @user.curr_role != "investor"
        # expect(page).to have_content(cc.fund.name)
        expect(page).to have_content( money_to_currency(cc.committed_amount) )
      else
        expect(page).not_to have_content(cc.investor.investor_name)
      end
    end
  end
end

Then('I should be able to see my capital remittances') do
  click_on("Calls")
  CapitalRemittance.all.each do |cc|
    puts "checking capital remittance for #{cc.investor.investor_name} against #{@investor.investor_name} "
    if cc.investor_id == @investor.id
      expect(page).to have_content(@investor.investor_name) if @user.curr_role != "investor"
      expect(page).to have_content( money_to_currency(cc.due_amount) )
      expect(page).to have_content( money_to_currency(cc.collected_amount) )
    else
      expect(page).not_to have_content(cc.investor.investor_name)
    end
  end
end


Given('there is a capital distribution {string}') do |args|
  @capital_distribution = FactoryBot.build(:capital_distribution, entity: @fund.entity, fund: @fund, approved: true)
  key_values(@capital_distribution, args)
  @capital_distribution.save!

  puts "\n####CapitalDistribution####\n"
  puts @capital_distribution.to_json

end

Then('I should be able to see my capital distributions') do
  click_on("Distributions")
  CapitalDistributionPayment.all.each do |cc|
    puts "checking capital distrbution payment for #{cc.investor.investor_name} against #{@investor.investor_name} "
    if cc.investor_id == @investor.id
      expect(page).to have_content(@investor.investor_name) if @user.curr_role != "investor"
      expect(page).to have_content( money_to_currency(cc.amount) )
      expect(page).to have_content( cc.payment_date.strftime("%d/%m/%Y") )
    else
      expect(page).not_to have_content(cc.investor.investor_name)
    end
  end
end



Given('the fund has capital call template') do
  @call_template = Document.create!(name: "Call Doc", owner_tag: "Call Template",
    owner: @fund, entity_id: @fund.entity_id, user: @user,
    file: File.new("public/sample_uploads/Drawdown notice format.docx", "r"))
end

Given('the fund has capital commitment template') do
  @commitment_template = Document.create!(name: "Fund Agreement", owner_tag: "Commitment Template",
    owner: @fund, entity_id: @fund.entity_id, user: @user,
    file: File.new("public/sample_uploads/Commitment Agreement Template.docx", "r"))
end

Then('the user goes to the fund e-signature report') do
  @template_dup = @commitment_template.dup
  @template_dup.assign_attributes(sent_for_esign: true, owner: @fund.capital_commitments.last )
  @template_dup.save!
  ESignature.create!(user: @user, entity: @fund.entity, document: @template_dup, status: "failed")
  visit(fund_path(@fund))
  click_on("Reports")
  click_on("E-Signatures Report")
  sleep(2)
end

Then('the user should see all esign report for all docs sent for esign') do
  esign = ESignature.last
  doc = esign.document
  expect(page).to have_content(doc.name)
  expect(page).to have_content(doc.owner_tag)
end

Then('when the capital commitment docs are generated') do
  CapitalCommitment.all.each do |cc|
    visit(capital_commitment_path(cc))
    find("#commitment_actions").click
    click_on("Generate All Documents")
    sleep(1)
    click_on("Proceed")
    sleep(8)
    expect(page).to have_content("Documentation generation started")
  end
end

Then('the generated doc must be attached to the capital commitments') do
  CapitalCommitment.all.each do |cc|
    cc.documents.where(name: @commitment_template.name, owner_tag: "Generated").count.should == 1
    visit(capital_commitment_path(cc))
    expect(page).to have_content(@commitment_template.name)
    expect(page).to have_content("Generated")
  end
end

Then('when the capital call docs are generated') do
  CapitalCall.all.each do |cc|
    visit(capital_call_path(cc))
    click_on("Generate Documents")
    # sleep(1)
    # expect(page).to have_content("Documentation generation started")
    sleep(20)
    # expect(page).to have_content("Document #{@call_template.name} generated")
  end
end

Then('the generated doc must be attached to the capital remittances') do
  CapitalRemittance.all.each do |cc|
    cc.documents.where(name: @call_template.name).count.should == 1
    visit(capital_remittance_path(cc))
    within("#remittance_details") do
      click_on("Documents")
      expect(page).to have_content(@call_template.name)
      expect(page).to have_content("Generated")
    end
  end
end


Given('each investor has a {string} kyc') do |status|
  verified = status == "verified"
  Investor.all.each do |inv|
    kyc = FactoryBot.create(:investor_kyc, investor: inv, entity: @fund.entity, verified:)
  end
end


Given('each investor has a {string} kyc linked to the commitment') do |status|
  verified = status == "verified"
  Investor.all.each do |inv|
    kyc = FactoryBot.build(:investor_kyc, investor: inv, entity: @fund.entity, verified:)
    kyc.save(validate: false)
    @fund.capital_commitments.where(investor_id: inv.id).update(investor_kyc_id: kyc.id)
  end
end


When('the fund document details must be setup right') do
  @fund.data_room_folder.name.should == "Data Room"
  @fund.data_room_folder.owner.should == @fund

  @document.owner.should == @fund
  @document.folder.name.should == "Data Room"
  @document.folder.full_path.should == "/Funds/#{@fund.name}/Data Room"
end

When('I visit the fund details page') do
  visit(fund_path(@fund))
end

When('I click on fund documents tab') do
  sleep(1)
  find("#documents_tab").click()
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


Given('the units are generated') do
  CapitalCall.all.each do |cc|
    FundUnitsJob.perform_now(cc.id, "CapitalCall", "Allocation for collected call amount", User.first.id)
  end
  CapitalDistribution.all.each do |cc|
    FundUnitsJob.perform_now(cc.id, "CapitalDistribution", "Redemption for distribution", User.first.id)
  end

end

Then('there should be correct units for the calls payment for each investor') do
  FundUnit.count.should == CapitalCommitment.count * CapitalCall.count
  CapitalCommitment.all.each do |cc|
    puts "Checking units for #{cc}"
    cc.fund_units.length.should
    cc.fund_units.each do |fu|
      ap fu
      fu.unit_type.should == cc.unit_type
      fu.owner_type.should == "CapitalRemittance"
      fu.price.should == fu.owner.capital_call.unit_prices[fu.unit_type]["price"].to_d
      amount_cents = fu.owner.collected_amount_cents < fu.owner.call_amount_cents ? fu.owner.collected_amount_cents : fu.owner.call_amount_cents
      fu.quantity.round(2).should == ( amount_cents / ((fu.price + fu.premium)* 100)).round(2)
    end
  end
end


Then('the corresponding distribution payments should be created') do
  CapitalDistributionPayment.count.should == CapitalCommitment.count
  CapitalDistributionPayment.all.each do |cdp|
    cdp.investor_id.should == cdp.capital_commitment.investor_id
    cdp.amount_cents.should == (@capital_distribution.net_amount_cents * cdp.capital_commitment.percentage / 100)
    cdp.folio_id.should == cdp.capital_commitment.folio_id
    cdp.capital_distribution_id.should == @capital_distribution.id
    cdp.investor_name.should == cdp.capital_commitment.investor_name
  end
end

Then('I should see the distribution payments') do
  visit(capital_distribution_path(@capital_distribution))
  CapitalDistributionPayment.all.each do |cdp|
    within("#capital_distribution_payment_#{cdp.id}") do
      expect(page).to have_content(cdp.investor_name)
      expect(page).to have_content(cdp.folio_id)
      expect(page).to have_content(money_to_currency(cdp.amount))
      expect(page).to have_content(cdp.completed ? "Yes" : "No")
    end
  end
end

Given('the distribution payments are completed') do
  puts CapitalDistributionPayment.all.to_json
  CapitalDistributionPayment.update(completed: true)
end

Then('there should be correct units for the distribution payments for each investor') do
  CapitalCommitment.all.each do |cc|
    puts "Checking units for #{cc}"
    cc.fund_units.length.should > 0
    cc.fund_units.each do |fu|
      ap fu
      fu.unit_type.should == cc.unit_type
      fu.owner_type.should == "CapitalDistributionPayment"
      fu.price.should == fu.owner.capital_distribution.unit_prices[fu.unit_type].to_d
      fu.quantity.should == -(fu.owner.cost_of_investment_cents / (fu.price * 100))
    end
  end
end


Then('Given I upload {string} file for Account Entries') do |file|
  @import_file = file
  visit(capital_commitment_path(@fund.capital_commitments.first))
  click_on("Account Entries")
  sleep(1)
  click_on("Upload")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  sleep(1)
  click_on("Save")
  sleep(1)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
  ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} account_entries created') do |count|
  AccountEntry.count.should == count.to_i
end

Then('the account_entries must have the data in the sheet') do
    file = File.open("./public/sample_uploads/#{@import_file}", "r")
    data = Roo::Spreadsheet.open(file.path) # open spreadsheet
    headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

    account_entries = @fund.account_entries.order(id: :asc).to_a
    data.each_with_index do |row, idx|
      next if idx.zero? # skip header row

      # create hash from headers and cells
      user_data = [headers, row].transpose.to_h
      ap user_data
      cc = account_entries[idx-1]
      ap cc

      puts "Checking import of #{cc.name}"
      cc.name.should == user_data["Name"].strip
      cc.fund.name.should == user_data["Fund"]
      cc.investor.investor_name.should == user_data["Investor"]
      cc.folio_id.should == user_data["Folio No"].to_s

      cc.amount_cents.should == user_data["Amount"].to_f * 100
      cc.entry_type.should == user_data["Entry Type"]
      cc.reporting_date.should == user_data["Reporting Date"]
      cc.notes.should == user_data["Notes"]
      cc.import_upload_id.should == ImportUpload.where(import_type: "AccountEntry").last.id
    end

end


Then('the account_entries must visible for each commitment') do
  @fund.account_entries.each do |ae|
    visit(capital_commitment_path(ae.capital_commitment))
    click_on "Account Entries"
    expect(page).to have_content(ae.name)
    expect(page).to have_content(ae.entry_type)
    if ae.name.include?("Percentage")
      expect(page).to have_content("#{ae.amount_cents} %")
    else
      expect(page).to have_content(money_to_currency(ae.amount, {}))
    end
    expect(page).to have_content(ae.capital_commitment.folio_id)
    expect(page).to have_content(ae.reporting_date.strftime("%d/%m/%Y"))
  end
end


Then('Given I upload {string} file for the remittances of the capital call') do |file|
  @import_file = file
  visit(capital_call_path(@fund.capital_calls.first))
  click_on("Remittances")
  sleep(2)
  click_on("Upload / Download")
  click_on("Upload Payments")
  sleep(2)
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  sleep(2)
  click_on("Save")
  sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
  ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} remittance payments created') do |count|
  CapitalRemittancePayment.count.should == count.to_i
end

Then('the capital remittance payments must have the data in the sheet') do
    file = File.open("./public/sample_uploads/#{@import_file}", "r")
    data = Roo::Spreadsheet.open(file.path) # open spreadsheet
    headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

    capital_remittance_payments = @fund.capital_remittance_payments.order(id: :asc).to_a
    data.each_with_index do |row, idx|
      next if idx.zero? # skip header row

      # create hash from headers and cells
      user_data = [headers, row].transpose.to_h

      cc = capital_remittance_payments[idx-1]
      cc.fund.name.should == user_data["Fund"]
      cc.capital_remittance.investor.investor_name.should == user_data["Investor"]
      cc.capital_remittance.folio_id.should == user_data["Folio No"].to_s
      cc.folio_amount_cents.should == user_data["Amount"].to_i * 100
      cc.reference_no.should == user_data["Reference No"].to_s
      cc.payment_date.should == user_data["Payment Date"]
      cc.import_upload_id.should == ImportUpload.last.id

      capital_commitment = cc.capital_remittance.capital_commitment
      capital_commitment.folio_currency.should == user_data["Currency"]

      amount = capital_commitment.foreign_currency? ? (cc.folio_amount_cents * capital_commitment.get_exchange_rate(capital_commitment.folio_currency, cc.fund.currency, cc.payment_date).rate) : cc.amount_cents
      cc.amount_cents.should == amount
      # sleep(30)
    end
end



Then('when the exchange rate changes') do
  foreign_currencies = @fund.capital_commitments.joins(:fund).where("folio_currency != funds.currency").all.pluck(:folio_currency).uniq
  foreign_currencies.each do |fc|
    # Change the exchange rate for the foreign_currencies randomly
    exchange_rate = ExchangeRate.where(from: fc, to: @fund.currency, latest: true).last.dup
    exchange_rate.rate += (rand(10) - rand(10) + 0.1)
    exchange_rate.save
  end
end

Then('the commitment amounts change correctly') do
  @fund.reload
  @fund.capital_commitments.each do |cc|
    cc.committed_amount_cents.should == cc.orig_committed_amount_cents + cc.adjustment_amount_cents
  end
end

Given('the last investor has a user {string}') do |args|
  cr = CapitalRemittance.first
  investor = cr.investor
  user = FactoryBot.create(:user,entity: investor.investor_entity, whatsapp_enabled: true)
  user1 = FactoryBot.create(:user,entity: investor.investor_entity)
  user2 = FactoryBot.create(:user,entity: investor.investor_entity, phone:"321")

  key_values(user,args)
  user.save!

  [user, user1].each do |u|
    user.add_role :investor_advisor
    AccessRight.create(entity_id: investor.investor_entity_id, owner: @fund, access_to_investor_id: investor.id,metadata: "Investor", user_id: u.id)
    ia = InvestorAccess.create(entity: investor.entity, investor: investor,
        first_name: u.first_name, last_name: u.last_name,
        email: u.email, granter: u, approved: true, is_investor_advisor: true)
    ia.update_columns(approved: true, is_investor_advisor: true)
    end
end

Given('the capital remittance whatsapp notification is sent to the first investor') do
  cr = CapitalRemittance.first
  cc = cr.capital_call
  cc.update_columns(approved:true, manual_generation: false)
  @resjob = cr.send_notification
end


Given('the fund has fund ratios') do
    FundRatiosJob.perform_now(@fund.id, nil, Time.zone.now + 2.days, @user.id, true)
end

Then('{string} has {string} "{string}" access to the fund_ratios') do |arg1,truefalse, accesses|
  args_temp = arg1.split(";").to_h { |kv| kv.split("=") }
  @user = if User.exists?(args_temp)
    User.find_by(args_temp)
  else
    FactoryBot.build(:user)
  end
  key_values(@user, arg1)
  @user.save!
  puts "##### Checking access to fund_ratios for funds with rights #{@fund.access_rights.to_json}"
  accesses.split(",").each do |access|
    @fund.fund_ratios.each do |fr|
      puts "##Checking access #{access} on fund_ratios from #{@fund.name} for #{@user.email} as #{truefalse}"
      Pundit.policy(@user, fr).send("#{access}?").to_s.should == truefalse
    end
  end
end

Given('Given I upload a fund unit setting file for the fund') do
  visit(fund_url(@fund))
  click_on("Actions")
  click_on("Fund Unit Settings")
  sleep(2)
  click_on("Upload")
  sleep(6)
  fill_in('import_upload_name', with: "Test Fund Unit Settings Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/fund_unit_setting.xlsx'), make_visible: true)
  sleep(3)
  click_on("Save")
  sleep(10)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
  ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} fund unit settings created with data in the sheet') do |count|
  file = File.open("./public/sample_uploads/fund_unit_setting.xlsx", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h
    FundUnitSetting.where(fund_id: Fund.find_by(name: row_data["Fund"]).id, name: row_data["Class/Series"], management_fee: row_data["Management Fee %"], setup_fee: row_data["Setup Fee %"], carry: row_data["Carry %"]).present?.should == true
  end
end

# Then('{string} has {string} "{string}" access to the fund_ratios') do |arg1,truefalse, accesses|
#   args_temp = arg1.split(";").to_h { |kv| kv.split("=") }
#   @user = if User.exists?(args_temp)
#     User.find_by(args_temp)
#   else
#     FactoryBot.build(:user)
#   end
#   key_values(@user, arg1)
#   @user.save!
#   puts "##### Checking access to fund_ratios for funds with rights #{@fund.access_rights.to_json}"
#   accesses.split(",").each do |access|
#     @fund.fund_ratios.each do |fr|
#       puts "##Checking access #{access} on fund_ratios from #{@fund.name} for #{@user.email} as #{truefalse}"
#       Pundit.policy(@user, fr).send("#{access}?").to_s.should == truefalse
#     end
#   end
# end


Then('Given I upload {string} file for Distributions of the fund') do |string|
  visit(capital_distributions_url)
  sleep(2)
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Test Distributions Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/capital_distributions.xlsx'), make_visible: true)
  sleep(3)
  click_on("Save")
  sleep(6)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
  ImportUpload.last.failed_row_count.should == 0
end

Then('Given I upload {string} file for Fund Units of the fund') do |string|
  visit(fund_units_url)
  sleep(2)
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Test Fund Units Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/fund_units.xlsx'), make_visible: true)
  sleep(3)
  click_on("Save")
  sleep(6)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
  ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} fund units created with data in the sheet') do |count|
  file = File.open("./public/sample_uploads/fund_units.xlsx", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h
    capital_commitment = CapitalCommitment.where(folio_id: row_data["Folio No"]).first

    fund_unit = FundUnit.where(capital_commitment_id: capital_commitment.id, quantity: row_data["Quantity"].to_f).first

    puts "Checking import of #{fund_unit.to_json}"

    fund_unit.quantity.should == row_data["Quantity"].to_f
    fund_unit.unit_type.should == row_data["Unit Type"]
    fund_unit.price.should == row_data["Price"].to_f
    fund_unit.premium.should == row_data["Premium"].to_f
    fund_unit.issue_date.should == row_data["Issue Date"]
    fund_unit.reason.should == row_data["Reason"]
    fund_unit.owner.folio_id.should == row_data["Folio No"].to_s

    if fund_unit.quantity.positive?
      fund_unit.owner_type.should == "CapitalRemittance"
    else
      fund_unit.owner_type.should == "CapitalDistributionPayment"
    end
  end
end

Given('there is a custom notification for the capital call with subject {string} with email_method {string}') do |subject, email_method|
  @custom_notification = CustomNotification.create!(entity: @capital_call.entity, subject:, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), owner: @capital_call, email_method:)
end

Given('Given the commitments have a cc {string}') do |email|
  @cc_email = email
  CapitalCommitment.all.each do |cc|
    cc.properties[:cc] = email
    cc.save
  end
end

Then('the investors must have access rights to the fund') do
  @fund.capital_commitments.each do |cc|
    ar = AccessRight.where(owner: @fund, access_to_investor_id: cc.investor_id, access_type: "Fund").first
    ar.should be_present
  end
end


When('a commitment adjustment {string} is created') do |args|
  @commitment_adjustment = CommitmentAdjustment.new(entity: @entity, capital_commitment: @capital_commitment, fund: @fund, as_of: Date.today, reason: "Test Adjustment")
  key_values(@commitment_adjustment, args)
  AdjustmentCreate.wtf?(commitment_adjustment: @commitment_adjustment)
end

Then('the capital commitment should have a committed amount {string}') do |committed_amount_cents|
  @capital_commitment.reload
  @capital_commitment.committed_amount_cents.should == committed_amount_cents.to_i
end

Then('the capital commitment should have a arrears amount {string}') do |arrear_amount_cents|
  @capital_commitment.reload
  @capital_commitment.arrear_amount_cents.should == arrear_amount_cents.to_i
end

When('a commitment adjustment {string} is created for the last remittance') do |args|
  @capital_remittance = @fund.capital_remittances.last
  @commitment_adjustment = CommitmentAdjustment.new(entity: @entity, capital_commitment: @capital_commitment, fund: @fund, as_of: Date.today, reason: "Test Adjustment", owner: @capital_remittance)
  key_values(@commitment_adjustment, args)
  AdjustmentCreate.wtf?(commitment_adjustment: @commitment_adjustment)
end

Then('the last remittance should have a arrears amount {string}') do |arrear_amount_cents|
  @capital_remittance.reload
  puts @capital_remittance.to_json
  @capital_remittance.arrear_amount_cents.should == arrear_amount_cents.to_i
end


Then('a reverse remittance payment must be generated for the remittance') do
  @capital_remittance.reload
  @reverse_payment = @capital_remittance.capital_remittance_payments.last
  @reverse_payment.fund_id.should == @capital_remittance.fund_id
  @reverse_payment.amount_cents.should == @capital_remittance.arrear_amount_cents
  @reverse_payment.folio_amount_cents.should == @capital_remittance.arrear_folio_amount_cents  
  @reverse_payment.amount_cents.should == @commitment_adjustment.amount_cents
  @reverse_payment.folio_amount_cents.should == @commitment_adjustment.folio_amount_cents
  @reverse_payment.payment_date.should == @commitment_adjustment.as_of
end

Then('the collected amounts must be computed properly') do
  @capital_call.reload
  @capital_remittance.reload
  @capital_commitment.reload

  @capital_call.collected_amount_cents.should == @capital_call.capital_remittances.sum(:collected_amount_cents)
  @capital_commitment.collected_amount_cents.should == @capital_commitment.capital_remittances.sum(:collected_amount_cents)
  @capital_commitment.folio_collected_amount_cents.should == @capital_commitment.capital_remittances.sum(:folio_collected_amount_cents)
end

Given('the remittances are verified') do
  CapitalRemittance.all.each do |cr|
    CapitalRemittanceVerify.wtf?(capital_remittance: cr)
  end
end


Given('notification should be sent {string} to the remittance investors for {string}') do |sent, cn_args|
  cn = CustomNotification.new
  key_values(cn, cn_args)
  
  @capital_call.capital_remittances.each do |cr|
    user = cr.investor.investor_accesses.approved.first.user
    open_email(user.email)
    puts "Checking email for #{user.email} with email_method: #{cn.email_method}, subject: #{current_email&.subject}"
    if sent == "true"
      expect(current_email.subject).to include @capital_call.custom_notification(cn.email_method).subject
    else
      current_email.should == nil
    end  
  end
  
end

Given('there is a custom notification {string} in place for the Call') do |args|
    @capital_call = CapitalCall.last
    @custom_notification = CustomNotification.build(entity: @entity, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), owner: @capital_call)
    key_values(@custom_notification, args)
    @custom_notification.save!
end

Then('the imported data must have the form_type updated') do
  @import_upload = ImportUpload.last
  @import_upload.imported_data.all.each do |row|
    form_type = @import_upload.entity.form_types.where(name: row.class.name).first
    if form_type.present?
      puts "Checking form_type for #{row.class.name}"
      row.form_type_id.should == form_type.id 
      form_type.form_custom_fields.each do |fcf|
        # Ensure that the data json fields are exactly the same as the form custom fields name
        puts "Checking #{fcf.name} in imported data #{row.custom_fields[fcf.name]}"
        row.custom_fields[fcf.name].should_not == nil
      end
    end
  end
end
