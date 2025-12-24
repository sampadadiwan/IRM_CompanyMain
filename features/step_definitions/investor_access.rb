Given('I fill the investor access form with {string}') do |args|
  @temp_ia = InvestorAccess.new
  key_values(@temp_ia, args)
  fill_in 'investor_access_email', with: @temp_ia.email if @temp_ia.email.present?
  fill_in 'investor_access_first_name', with: @temp_ia.first_name if @temp_ia.first_name.present?
  fill_in 'investor_access_last_name', with: @temp_ia.last_name if @temp_ia.last_name.present?
  fill_in 'investor_access_phone', with: @temp_ia.phone if @temp_ia.phone.present?
  if @temp_ia.approved
    check 'investor_access_approved'
  else
    uncheck 'investor_access_approved'
  end
  if @temp_ia.email_enabled
    check 'investor_access_email_enabled'
  else
    uncheck 'investor_access_email_enabled'
  end
  fill_in 'investor_access_cc', with: @temp_ia.cc if @temp_ia.cc.present?
end

And('investor access stakeholders are {string}') do |visibility|
  @stakeholder_column_visible = visibility == 'visible'
  puts "Checking investor access stakeholders are #{@stakeholder_column_visible ? 'visible' : 'not visible'}"
end

Then('I should see the new investor access in the investor access list') do
  @investor_access = InvestorAccess.last
  puts "Checking presence of investor access #{@investor_access.email} in list"
  within('#investor_accesses_table_body') do
    within("#investor_access_#{@investor_access.id}") do
      if @stakeholder_column_visible
        puts "Checking stakeholder column is visible"
        expect(page).to have_content(@investor_access.investor_name)
      else
        puts "Checking stakeholder column is not visible"
        expect(page).not_to have_content(@investor_access.investor_name)
      end
      expect(page).to have_content(@investor_access.email)
      expect(page).to have_content(@investor_access.first_name)
      expect(page).to have_content(@investor_access.last_name)
      expect(page).to have_content(@investor_access.phone) if @investor_access.phone.present?
      expect(page).to have_content(@investor_access.cc) if @investor_access.cc.present?
      if @investor_access.approved
        expect(page).to have_content('UnApprove')
      else
        expect(page).to have_content('Approve')
      end
    end
  end
end

Given('I {string} the investor access for {string}') do |action, email|
  @investor_access = InvestorAccess.find_by(email: email)
  expect(@investor_access).to be_present
  puts "Performing #{action} on investor access #{@investor_access.email}"
  if action == 'approve'
    within("#investor_access_#{@investor_access.id}") do
      click_on 'Approve'
    end
    sleep(0.5)
    expect(@investor_access.reload.approved).to be true
    expect(page).to have_content('Approved '+@investor_access.email)
  elsif action == 'unapprove'
    within("#investor_access_#{@investor_access.id}") do
      click_on 'UnApprove'
    end
    sleep(0.5)
    expect(@investor_access.reload.approved).to be false
    expect(page).to have_content('Un-approved '+@investor_access.email)
  elsif action == 'delete'
    within("#investor_access_#{@investor_access.id}") do
      click_on("Actions")
      click_on 'Delete'
    end
    click_on 'Proceed'
    sleep(0.5)
    expect(InvestorAccess.find_by(email: email)).to be_nil
    expect(page).to have_content('Destroyed '+@investor_access.email)
  else
    raise "Unknown action #{action}"
  end
end

Given('I click on {string} for the investor access for {string}') do |text, email|
  @investor_access = InvestorAccess.find_by(email: email)
  expect(@investor_access).to be_present
  puts "Clicking on #{text} for investor access #{@investor_access.email}"
  within("#investor_access_#{@investor_access.id}") do
    click_on("Actions") if ["Edit", "Delete"].include?(text)
    click_on text
  end
end

Then('I should see the updated investor access in the investor access list') do
  @investor_access.reload
  puts "Checking updated presence of investor access #{@investor_access.email} in list"
  within('#investor_accesses_table_body') do
    within("#investor_access_#{@investor_access.id}") do
      if @stakeholder_column_visible
        puts "Checking stakeholder column is visible"
        expect(page).to have_content(@investor_access.investor_name)
      else
        puts "Checking stakeholder column is not visible"
        expect(page).not_to have_content(@investor_access.investor_name)
      end
      expect(page).to have_content(@investor_access.email)
      expect(page).to have_content(@investor_access.first_name)
      expect(page).to have_content(@investor_access.last_name)
      expect(page).to have_content(@investor_access.phone) if @investor_access.phone.present?
      expect(page).to have_content(@investor_access.cc) if @investor_access.cc.present?
      if @investor_access.approved
        expect(page).to have_content('UnApprove')
      else
        expect(page).to have_content('Approve')
      end
    end
  end
end

Then('the investor access should be removed from the investor access list') do
  puts "Checking removal of investor access #{@investor_access.email} from list"
  @investor_access.reload
  expect(@investor_access.deleted?).to be true
  expect(page).not_to have_selector("#investor_access_#{@investor_access.id}")
  expect(page).not_to have_content(@investor_access.first_name)
  expect(page).not_to have_content(@investor_access.last_name)
end

Given('I go to all investor accesses page') do
  visit("/investor_accesses")
end



Given('another user has investor access {string} in the investor') do |arg|
  @investor_access = InvestorAccess.new(entity: @entity, investor: @investor,
                                        first_name: @another_user.first_name, last_name: @another_user.last_name,
                                        email: @another_user.email, granter: @user)
  key_values(@investor_access, arg)

  @investor_access.save!
  puts "\n####Investor Access####\n"
  puts @investor_access.to_json
end


Given('investor access {string} in the portfolio company') do |arg|
  Investor.portfolio_companies.each do |pc|
    puts "Portfolio Company: #{pc.investor_name}, creating investor access for its employees"

    pc.investor_entity.employees.each do |emp|
      @investor_access = InvestorAccess.new(entity: pc.entity, investor: pc,
                                            first_name: emp.first_name, last_name: emp.last_name,
                                            email: emp.email, granter: @user)
      key_values(@investor_access, arg)

      @investor_access.save!
      puts "\n####Investor Access####\n"
      puts @investor_access.to_json
    end
  end
end