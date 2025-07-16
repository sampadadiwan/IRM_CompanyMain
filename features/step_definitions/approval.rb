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

  When('I create a new approval {string} for the fund') do |arg1|
    @approval = FactoryBot.build(:approval)
    key_values(@approval, arg1)

    visit(fund_path(@fund))
    click_on("Actions")
    click_on("Fund Approval")
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
    # find(".show_details_link").click
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
        within(".responses_count") do
          @approval&.response_status&.split(',')&.each do |status|
            expect(page).to have_content(status + " : " + @approval.approval_responses.where(status: status).count.to_s)
          end
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
    @user.entity.investors.each do |inv|
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


  When('the approval is approved internally') do
    @approval.approved = true
    ApprovalApprove.wtf?(approval: @approval).success?.should == true
  end

  Then('the investor gets the approval notification') do
    sleep(2)
    puts "\n#### Emails ###\n"
    puts @approval.pending_investors.collect(&:emails).flatten

    @approval.pending_investors.collect(&:emails).flatten.each do |email|
        open_email(email)
        @custom_notification ||= nil
        if @custom_notification.present?
          puts "current_email = to: #{current_email.to}, subj: #{current_email.subject}, body: #{@custom_notification.body}"
          expect(current_email.subject).to have_content @custom_notification.subject
          expect(current_email.body).to have_content @custom_notification.body
        else
          puts "current_email = to: #{current_email.to}, subj: #{current_email.subject}"
          expect(current_email.subject).to have_content "Approval required for #{@approval.entity.name}: #{@approval.title}"
        end
    end

    clear_emails
  end

  Then('the investor gets the approval custom notification') do
    puts "\n#### Emails ###\n"
    puts @approval.pending_investors.collect(&:emails).flatten

    @approval.pending_investors.collect(&:emails).flatten.each do |email|
        open_email(email)

        @custom_notification.should_not be_nil
        puts "current_email = to: #{current_email.to}, subj: #{current_email.subject}, body: #{@custom_notification.body}"
        expect(current_email.subject).to have_content @custom_notification.subject
        expect(current_email.body).to have_content @custom_notification.body

        if @approval.response_enabled_email
          
          statuses = @approval.response_status.split(',') - ["Pending"]
          statuses.each do |status|
            expect(current_email.body).to have_content status
          end
        else
          expect(current_email.body).not_to have_content "You may respond by clicking on any one of the below links or login to view the detailed approval and respond thereafter"
        end

        if @approval.enable_approval_show_kycs
          expect(current_email.body).to have_content "KYCs in this approval"
        else
          expect(current_email.body).not_to have_content "KYCs in this approval"
        end
    end

    clear_emails
  end


  Then('I should see my approval response') do
    @approval.approval_responses.pending.each do |response|
      within("#approval_response_#{response.id}") do
        # expect(page).to have_content(response.investor.investor_name)
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
          expect(current_email.subject).to eq "#{approval_response.entity.name}: #{approval_response.status} for #{approval_response.approval.title}"
        end
    end

    clear_emails
  end

  When('the Send Reminder button on approval is clicked') do
    visit(approval_url(@approval))
    click_on("Send Reminder")
    sleep(1)
    click_on("Proceed")
    sleep(1)
    expect(page).to have_content("Successfully sent reminder")
  end

  Then('the approval response is {string}') do |arg|
    sleep(1)
    @approval.reload
    @approval_response = @approval.approval_responses.first
    @approval_response.status.should == arg
  end

  
Then('the approval response user is correctly captured') do
  @approval_response.response_user_id.should == @approval_response.investor.investor_accesses.approved.first.user_id
end


  Then('the approved count of the approval is {string}') do |arg|
    @approval.approved_count.should == arg.to_i
  end

  Then('the rejected count of the approval is {string}') do |arg|
    @approval.rejected_count.should == arg.to_i
  end


When('I select {string} for the approval response') do |response|
  select(response, from: "approval_response_status")
  click_on("Submit")
end

Given('there is a custom notification in place for the approval with subject {string} with email_method {string}') do |subject, email_method|  
  @custom_notification = CustomNotification.create!(entity: @approval.entity, subject:, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), owner: @approval, email_method:)
end

Then('I should see the approval response details for each response') do 
  @approval.approval_responses.each do |response|
    within("#approval_response_#{response.id}") do
      click_on("Show")
    end

    expect(page).to have_content(@approval.to_s)
    expect(page).to have_content(response.investor.investor_name)
    expect(page).to have_content(response.status)

    visit(approval_path(@approval))
  
  end
end

When('I select {string} in the approval notification email') do |status|
  investor = @approval.approval_responses.last.investor
  email = investor.emails.last
  open_email(email)
  puts "clicking #{status} in current_email = to: #{current_email.to}, subj: #{current_email.subject}"
  current_email.click_link status
  ap @approval.approval_responses.last
end

When('the approval reminder is sent internally') do
  ApprovalReminder.wtf?(approval: @approval).success?.should == true
end


Then('the approval should have the right access rights') do
  if @approval.owner_type == "Fund"
    @approval.owner.access_rights.count.should == @approval.access_rights.count
    @approval.owner.access_rights.each do |ar|
      puts "Checking Access Right: #{ar}"
      @approval.access_rights.where(access_to_investor_id: ar.access_to_investor_id).count.should == 1
    end    
  else
    puts "No owner access rights copied"
    @approval.access_rights.count.should == 0
  end
end

Then('the approval should have the right approval responses created') do
  if @approval.owner
    @approval.approval_responses.each do |approval_response|
      # The approval response should be created for the right owner
      puts "Checking Approval Response Owner: #{approval_response.owner}"
      @approval.owner.approval_for(approval_response.investor_id).include?(approval_response.owner).should == true
    end
  else
    @approval.approval_responses.each do |approval_response|
      approval_response.owner.should == nil
    end
  end
end