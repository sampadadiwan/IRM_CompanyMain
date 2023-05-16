  Given('I am at the approvals page') do
    visit(approvals_url)
  end
  
  When('I create a new approval {string}') do |arg1|
    @approval = FactoryBot.build(:approval)
    key_values(@approval, arg1)

    click_on("New Approval")
    fill_in('approval_title', with: @approval.title)
    fill_in('approval_due_date', with: @approval.due_date)
    find('trix-editor').click.set(@approval.agreements_reference.body.to_plain_text)
    click_on("Save")
  end
  
  Then('an approval should be created') do
    db_approval = Approval.last
    db_approval.title.should == @approval.title
    db_approval.due_date.should == @approval.due_date
    db_approval.agreements_reference.body.to_plain_text.should == @approval.agreements_reference.body.to_plain_text

    @approval = db_approval
  end
  
  Then('I should see the approval details on the details page') do
    expect(page).to have_content(@approval.title)
    expect(page).to have_content(@approval.due_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(@approval.agreements_reference.body.to_plain_text)
    within("#approval_#{@approval.id}") do
        within(".approved_count") do
            expect(page).to have_content(@approval.approved_count)
        end
        within(".pending_count") do
            expect(page).to have_content(@approval.pending_count)
        end
        within(".rejected_count") do
            expect(page).to have_content(@approval.rejected_count)
        end
    end
  end
  
  Then('I should see the approval in all approvals page') do
    visit(approvals_url)
    expect(page).to have_content(@approval.title)
    expect(page).to have_content(@approval.due_date.strftime("%d/%m/%Y"))
    # expect(page).to have_content(@approval.agreements_reference)
    within("#approval_#{@approval.id}") do
        within(".approved_count") do
            expect(page).to have_content(@approval.approved_count)
        end
        within(".pending_count") do
            expect(page).to have_content(@approval.pending_count)
        end
        within(".rejected_count") do
            expect(page).to have_content(@approval.rejected_count)
        end
    end
  end
  

  When('I edit the approval {string}') do |arg1|
    key_values(@approval, arg1)
    @approval.due_date = @approval.due_date + 1.week
    visit(edit_approval_url(@approval))

    fill_in('approval_title', with: @approval.title)
    fill_in('approval_due_date', with: @approval.due_date)
    find('trix-editor').click.set(@approval.agreements_reference.body.to_plain_text)
    click_on("Save")
  end


  Given('there is an approval {string} for the entity') do |args|
    @approval = FactoryBot.create(:approval, entity: @user.entity)
    key_values(@approval, args)
    @approval.save
    puts "\n####Approval####\n"
    puts @approval.to_json
  end
  
  Given('the investors are added to the approval') do
    @user.entity.investors.not_holding.not_trust.each do |inv|
        ar = AccessRight.create!( owner: @approval, access_type: "Approval", 
                                 access_to_investor_id: inv.id, entity: @user.entity)


        puts "\n####Granted Access####\n"
        puts ar.to_json                            
    end    
  end

  When('I visit the approval details page') do
    visit(approval_url(@approval))
  end
  
  
  Then('the approval responses are generated with status {string}') do |string|
    sleep(2)
    @approval.reload
    @approval.approval_responses.pending.count.should > 0 
    @approval.approval_responses.pending.count.should == @approval.pending_investors.count
  end

  When('the approval is approved') do
    visit(approval_url(@approval))
    click_on("Approve")
    click_on("Proceed")    
    sleep(1)
    @approval.reload
    @approval.approved.should == true
  end
  
  Then('the investor gets the approval notification') do
    puts "\n#### Emails ###\n"
    puts @approval.pending_investors.collect(&:emails).flatten
    
    @approval.pending_investors.collect(&:emails).flatten.each do |email|
        open_email(email)
        puts "current_email = to: #{current_email.to}, subj: #{current_email.subject}"
        expect(current_email.subject).to eq "Approval required by #{@approval.entity.name}: #{@approval.title}"
    end
  end 
  

  Then('I should see my approval response') do
    @approval.approval_responses.pending.each do |response|
      within("#approval_response_#{response.id}") do
        expect(page).to have_content(response.investor.investor_name)
        expect(page).to have_content(response.status)
      end
    end

  end

  Then('when the approval response is accepted') do
    @approval.approval_responses.update(status: "Accepted")
  end
  
  Then('the investor gets the accepted notification') do
    puts "\n#### Emails ###\n"
    
    @approval.approval_responses.each do |approval_response|
        investor = approval_response.investor
        investor.emails.each do |email|
          open_email(email)
          puts "current_email = to: #{current_email.to}, subj: #{current_email.subject}"
          expect(current_email.subject).to eq "Approval response from #{approval_response.investor.investor_name}: #{approval_response.status}"
        end
    end
  end

  When('the Send Reminder button on approval is clicked') do
    visit(approval_url(@approval))
    click_on("Send Reminder")
  end
 
  Then('the approval response is {string}') do |arg|
    sleep(1)
    @approval.reload
    @approval_response = @approval.approval_responses.first
    @approval_response.status.should == arg
  end
  
  Then('the approved count of the approval is {string}') do |arg|
    @approval.approved_count.should == arg.to_i
  end
  
  Then('the rejected count of the approval is {string}') do |arg|
    @approval.rejected_count.should == arg.to_i
  end
  
  
  
  