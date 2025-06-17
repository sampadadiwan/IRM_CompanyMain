Given('I am {string} employee access to the fund') do |given|
  if given == "given" || given == "yes"
    @access_right = AccessRight.new(entity_id: @fund.entity_id, owner: @fund, user_id: @user.id)
    @access_right.permissions.set(:read)
    @access_right.save!
    @user.reload
  end
end

Given('another user is {string} investor access to the fund') do |given|
  # Hack to make the tests work without rewriting many steps for another user
  @user = @employee_investor
  if given == "given" || given == "yes"
    @access_right = AccessRight.create!(entity_id: @fund.entity_id, owner: @fund, access_to_investor_id: @investor.id, metadata: "Investor")

    ia = InvestorAccess.create!(entity: @investor.entity, investor: @investor,
      first_name: @user.first_name, last_name: @user.last_name,
      email: @user.email, granter: @user, approved: true )

    puts "\n####Investor Access####\n"
    puts ia.to_json
  end

  @fund.reload
  @user.reload
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

        # Create the Access Right
        @access_right = AccessRight.create!(entity_id: inv.investor_entity_id, owner: @fund, user_id: @user.id, metadata: "Investor Advisor")

        puts "\n####Access Right####\n"
        puts @access_right.to_json

        ia = InvestorAccess.create(entity: inv.entity, investor: inv,
        first_name: @user.first_name, last_name: @user.last_name,
        email: @user.email, granter: nil, approved: true )

        puts "\n####Investor Access####\n"
        puts ia.to_json


        # Switch the IA to the entity
        investor_advisor.switch(@user)

      end
    end

  end

  @fund.reload
  @user.reload
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
        @user.reload


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
    @user.reload
    puts "####### AccessRight #######\n"
    puts @access_right.to_json
  end
end



Then('user {string} have {string} access to the fund') do |truefalse, accesses|
  accesses.split(",").each do |access|
    puts "##Checking access #{access} on fund #{@fund.name} for #{@user.email} as #{truefalse}"
    Pundit.policy(@user, @fund).send("#{access}?").to_s.should == truefalse
  end
end

Then('user {string} have {string} access to the fund unit settings') do |truefalse, accesses|
  accesses.split(",").each do |access|
    @fund.fund_unit_settings.each do |fus|
      puts "##Checking access #{access} on FUS #{fus} for #{@user.email} as #{truefalse}"
      if @user.curr_role == "employee"
        Pundit.policy(@user, fus).send("#{access}?").to_s.should == truefalse
      elsif @user.curr_role == "investor"
        Pundit.policy(@user, fus).send("#{access}?").to_s.should == "false"
      else
        Pundit.policy(@user, fus).send("#{access}?").to_s.should == "false"
      end
    end
  end
end

Then('user {string} have {string} access to the fund units') do |truefalse, accesses|
  accesses.split(",").each do |access|
    @fund.fund_units.each do |fu|
      puts "##Checking access #{access} on Fund Unit #{fu} for #{@user.email} as #{truefalse}"
      if @user.curr_role == "employee"
        Pundit.policy(@user, fu).send("#{access}?").to_s.should == truefalse
      elsif @user.curr_role == "investor" && fu.investor.investor_entity_id == @user.entity_id
        Pundit.policy(@user, fu).send("#{access}?").to_s.should == truefalse
      else
        Pundit.policy(@user, fu).send("#{access}?").to_s.should == "false"
      end
    end
  end
end

Then('user {string} have {string} access to the fund formulas') do |truefalse, accesses|
  accesses.split(",").each do |access|
    @fund.fund_formulas.each do |ff|
      puts "##Checking access #{access} on Fund Formula #{ff} for #{@user.email} as #{truefalse}"
      if @user.curr_role == "employee"
        Pundit.policy(@user, ff).send("#{access}?").to_s.should == truefalse
      else
        Pundit.policy(@user, ff).send("#{access}?").to_s.should == "false"
      end
    end
  end
end


Then('user {string} have {string} access to the portfolio investments') do |truefalse, accesses|
  accesses.split(",").each do |access|
    @fund.portfolio_investments.each do |pi|
      puts "##Checking access #{access} on Portfolio Investment #{pi} for #{@user.email} as #{truefalse}"
      if @user.curr_role == "employee"
        Pundit.policy(@user, pi).send("#{access}?").to_s.should == truefalse
      elsif @user.curr_role == "investor"
        Pundit.policy(@user, pi).send("#{access}?").to_s.should == truefalse
      else
        Pundit.policy(@user, pi).send("#{access}?").to_s.should == "false"
      end
    end
  end
end

Then('user {string} have {string} access to the aggregate portfolio investments') do |truefalse, accesses|
  accesses.split(",").each do |access|
    @fund.aggregate_portfolio_investments.each do |pi|
      puts "##Checking access #{access} on Portfolio Investment #{pi} for #{@user.email} as #{truefalse}"
      if @user.curr_role == "employee"
        Pundit.policy(@user, @fund).send("#{access}?").to_s.should == truefalse
      elsif @user.curr_role == "investor"
        Pundit.policy(@user, @fund).send("#{access}?").to_s.should == truefalse
      else
        Pundit.policy(@user, @fund).send("#{access}?").to_s.should == "false"
      end
    end
  end
end

Then('user {string} have {string} access to the fund ratios') do |truefalse, accesses|
  accesses.split(",").each do |access|
    @fund.fund_ratios.each do |fr|
      puts "##Checking access #{access} on Fund Ratio #{fr} for #{@user.email} as #{truefalse}"
      # Fund Ratios cannot be edited or destroyed
      truefalse = "false" if ["edit", "update", "destroy"].include? access
      if @user.curr_role == "employee"
        Pundit.policy(@user, fr).send("#{access}?").to_s.should == truefalse
      elsif @user.curr_role == "investor"
        Pundit.policy(@user, fr).send("#{access}?").to_s.should == truefalse
      else
        Pundit.policy(@user, fr).send("#{access}?").to_s.should == "false"
      end
    end
  end
end


Then('user {string} have {string} access to the capital commitment') do |truefalse, accesses|
  @fund.reload
  puts @fund.access_rights.to_json
  accesses.split(",").each do |access|
    @fund.capital_commitments.includes(:investor).each do |cc|
      puts "##Checking access #{access} on capital_commitment from #{cc.investor.investor_name} for #{@user.email} as #{truefalse}"
      if @user.curr_role == "employee"
        Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
      elsif @user.curr_role == "investor" && cc.investor.investor_entity_id == @user.entity_id
        Pundit.policy(@user, cc).send("#{access}?").to_s.should == truefalse
      else
        Pundit.policy(@user, cc).send("#{access}?").to_s.should == "false"
      end
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

Given('the fund right has access {string}') do |crud|
  if @access_right
    crud.split(",").each do |p|
      @access_right.permissions.set(p.to_sym)
    end
    @access_right.save!
    @user.reload
    puts "####### AccessRight Permissions #######\n"
    ap @access_right
  end
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

Then('the investors must have access rights to the fund') do
  @fund.capital_commitments.each do |cc|
    ar = AccessRight.where(owner: @fund, access_to_investor_id: cc.investor_id, access_type: "Fund").first
    ar.should be_present
  end
end

Then('user should see the access rights of the fund {string}') do |crud|
  visit("funds/#{@fund.id}")
  click_on("Access")
  expect(page).to have_content(@investor.investor_name)
  crud.split(",").each do |access|
    expect(page).to have_content(access)
  end
end