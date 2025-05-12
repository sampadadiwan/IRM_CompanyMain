
  include CurrencyHelper
  include ActionView::Helpers::SanitizeHelper

  Given('I am at the investment_opportunities page') do
    visit(investment_opportunities_url)
  end

  When('I create a new investment_opportunity {string}') do |arg1|
    @investment_opportunity = FactoryBot.build(:investment_opportunity)
    key_values(@investment_opportunity, arg1)

    click_on("New Investment Opportunity")
    fill_in('investment_opportunity_company_name', with: @investment_opportunity.company_name)
    fill_in('investment_opportunity_fund_raise_amount', with: @investment_opportunity.fund_raise_amount)
    fill_in('investment_opportunity_min_ticket_size', with: @investment_opportunity.min_ticket_size)
    fill_in('investment_opportunity_last_date', with: @investment_opportunity.last_date)
    fill_in('investment_opportunity_currency', with: @investment_opportunity.currency)
    find('trix-editor').click.set(@investment_opportunity.details.to_plain_text)
    click_on("Save")
  end

  Then('an investment_opportunity should be created') do
    db_investment_opportunity = InvestmentOpportunity.last
    db_investment_opportunity.company_name.should == @investment_opportunity.company_name
    db_investment_opportunity.details.to_plain_text == @investment_opportunity.details.to_plain_text
    db_investment_opportunity.fund_raise_amount_cents.should == @investment_opportunity.fund_raise_amount_cents
    db_investment_opportunity.min_ticket_size_cents.should == @investment_opportunity.min_ticket_size_cents
    db_investment_opportunity.last_date.should == @investment_opportunity.last_date
    db_investment_opportunity.currency.should == @investment_opportunity.currency
    @investment_opportunity = db_investment_opportunity  end

  Then('I should see the investment_opportunity details on the details page') do
    visit(investment_opportunity_path(@investment_opportunity))
    find(".show_details_link").click
    expect(page).to have_content(@investment_opportunity.company_name)
    expect(page).to have_content(money_to_currency @investment_opportunity.fund_raise_amount)
    expect(page).to have_content(money_to_currency @investment_opportunity.min_ticket_size)
    expect(page).to have_content(@investment_opportunity.last_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(@investment_opportunity.currency)
    expect(page).to have_content(@investment_opportunity.details.to_plain_text)
  end

  Then('I should see the investment_opportunity in all investment_opportunities page') do
    visit(investment_opportunities_path)
    force_units = @investment_opportunity.default_currency_units
    expect(page).to have_content(@investment_opportunity.company_name)
    expect(page).to have_content(money_to_currency @investment_opportunity.fund_raise_amount, {force_units: })

    if force_units == "Crores" && @investment_opportunity.min_ticket_size.to_d < 100_00000
      # If committed_amount is less than a crore, then show in lakhs
      force_units = "Lakhs"
    end
    expect(page).to have_content(money_to_currency @investment_opportunity.min_ticket_size, {force_units:})
    expect(page).to have_content(@investment_opportunity.last_date.strftime("%d/%m/%Y"))
  end


  Given('there is an investment_opportunity {string}') do |arg1|
    @investment_opportunity = FactoryBot.build(:investment_opportunity, entity: @entity)
    key_values(@investment_opportunity, arg1)
    @investment_opportunity.save!

    puts "\n####InvestmentOpportunity####\n"
    puts @investment_opportunity.to_json
  end

  Given('the investors are added to the investment_opportunity') do
    @user.entity.investors.each do |inv|
        ar = AccessRight.create!( owner: @investment_opportunity, access_type: "InvestmentOpportunity",
                                 access_to_investor_id: inv.id, entity: @user.entity)


        puts "\n####Granted Access####\n"
        puts ar.to_json
    end

  end

  When('I upload a document for the investment_opportunity') do
    visit(investment_opportunity_path(@investment_opportunity))
    click_on "Actions"
    click_on "New Document"
    fill_in('document_name', with: "Test IO Doc")
    # select("Document", from: "document_tag_list")
    attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)
    sleep(2)
    check('Send email', allow_label_click: true)
    click_on("Save")
    expect(page).to have_content("successfull")
    # #sleep(2)
  end

  Then('The document must be created with the owner set to the investment_opportunity') do
    @document = Document.last
    puts "\n####Uploaded Doc####\n"
    puts @document.to_json
    @investment_opportunity.reload
    @investment_opportunity.documents.first.should == @document
  end



  When('I create an EOI {string}') do |arg1|
    @expression_of_interest = FactoryBot.build(:expression_of_interest)
    key_values(@expression_of_interest, arg1)

    visit(investment_opportunity_path(@investment_opportunity))
    click_on "Interests"
    click_on "New Interest"
    fill_in('expression_of_interest_amount', with: @expression_of_interest.amount.to_i)
    # select(@expression_of_interest.investor.investor_name, from: "expression_of_interest_investor_id")
    find('trix-editor').click.set(@expression_of_interest.details.to_plain_text)
    #sleep(2)
    click_on("Save")
    expect(page).to have_content("successfull")
    # sleep(2)
  end

  Then('the EOI must be created') do
    db_expression_of_interest = ExpressionOfInterest.last

    puts "\n####EOI####\n"
    puts db_expression_of_interest.to_json

    db_expression_of_interest.entity_id.should == @investment_opportunity.entity_id
    db_expression_of_interest.investment_opportunity_id.should == @investment_opportunity.id
    db_expression_of_interest.investor_id.should == @expression_of_interest.investor_id
    db_expression_of_interest.amount_cents.should == @expression_of_interest.amount_cents
    db_expression_of_interest.details.to_plain_text.should == @expression_of_interest.details.to_plain_text
    @expression_of_interest = db_expression_of_interest
  end

  Then('I should see the EOI details on the details page') do
    visit(expression_of_interest_path(@expression_of_interest))
    expect(page).to have_content(@expression_of_interest.investor.investor_name)
    expect(page).to have_content(money_to_currency @expression_of_interest.amount)
    expect(page).to have_content(@expression_of_interest.details.to_plain_text)
    expect(page).to have_content(@expression_of_interest.user.full_name)
  end

  Then('I should see the EOI in all EOIs page') do
    visit(investment_opportunity_path(@investment_opportunity))
    click_on "Interests"
    expect(page).to have_content(@expression_of_interest.investor.investor_name)
    expect(page).to have_content(money_to_currency @expression_of_interest.amount)
    expect(page).to have_content(@expression_of_interest.user.full_name)
  end


  Then('the investment_opportunity eoi amount should be {string}') do |amount|
    puts @investment_opportunity.reload.to_json
    @investment_opportunity.eoi_amount_cents.should == amount.to_i
  end

  Then('when the EOI is approved') do
    visit(investment_opportunity_path(@investment_opportunity))
    click_on "Interests"
    within("#expression_of_interest_#{@expression_of_interest.id}") do
      click_on "Approve"
    end
    within(".eoi_approved") do
      expect(page).to have_content("Yes")
    end
    
    #sleep(1)
  end

  When('I add widgets for the investment_opportunity') do
    visit(investment_opportunity_path(@investment_opportunity))
    click_on("Widgets")
    click_on("New Widget")
    fill_in('ci_widget_title', with: "Left Widget")
    select("Left", from: "ci_widget_image_placement")
    details_top_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[3]/trix-editor")
    details_top_element.set("Left Widget Intro")
    details_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[4]/trix-editor")
    details_element.set("Left Widget Details")
    attach_file('files[]', File.absolute_path("./public/img/logo_big.png"), make_visible: true)
    sleep(2)
    click_on("Save")
    expect(page).to have_content("successfull")

    visit(investment_opportunity_path(@investment_opportunity))
    click_on("Widgets")
    click_on("New Widget")
    fill_in('ci_widget_title', with: "Center Widget")
    select("Center", from: "ci_widget_image_placement")
    details_top_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[3]/trix-editor")
    details_top_element.set("Center Widget Intro")
    details_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[4]/trix-editor")
    details_element.set("Center Widget Details")
    attach_file('files[]', File.absolute_path("./public/img/logo_big.png"), make_visible: true)
    sleep(2)
    click_on("Save")
    expect(page).to have_content("successfull")

    visit(investment_opportunity_path(@investment_opportunity))
    click_on("Widgets")
    click_on("New Widget")
    fill_in('ci_widget_title', with: "Right Widget")
    select("Right", from: "ci_widget_image_placement")
    details_top_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[3]/trix-editor")
    details_top_element.set("Right Widget Intro")
    details_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[4]/trix-editor")
    details_element.set("Right Widget Details")
    # fill_in('ci_widget_details_top', with: "Right Widget Intro")
    # fill_in('ci_widget_details', with: "Right Widget Details")
    attach_file('files[]', File.absolute_path("./public/img/logo_big.png"), make_visible: true)
    sleep(2)
    click_on("Save")
    expect(page).to have_content("successfull")
  end

  When('I add track record for the investment_opportunity') do
    visit(investment_opportunity_path(@investment_opportunity))
    click_on("Track Record")
    click_on("New Track Record")
    fill_in('ci_track_record_name', with: "Test Track Record")
    fill_in('ci_track_record_prefix', with: "good")
    fill_in('ci_track_record_value', with: "250000")
    fill_in('ci_track_record_suffix', with: "bad")
    fill_in('ci_track_record_details', with: "Track record details")
    click_on("Save")
    expect(page).to have_content("successfull")
  end

  When('I go to investment_opportunity preview') do
    visit(investment_opportunity_path(@investment_opportunity))
    click_on("Preview")
  end

  Then('I can see all the investment_opportunity preview details') do
    @investment_opportunity.ci_widgets.each do |widget|
      expect(page).to have_content(widget.title)
      expect(page).to have_content(widget.details_top.gsub(/<\/?div>/, ''))
      expect(page).to have_content(widget.details.gsub(/<\/?div>/, ''))
    end
    @investment_opportunity.ci_track_records.each do |track_record|
      expect(page).to have_content(track_record.name)
      expect(page).to have_content(track_record.prefix)
      expect(page).to have_content(track_record.value)
      expect(page).to have_content(track_record.suffix)
      expect(page).to have_content(track_record.details.gsub(/<\/?div>/, ''))
    end
    @investment_opportunity.documents.each do |doc|
      expect(page).to have_content(doc.name)
    end
  end

  When('the RM create an EOI {string} and the corresponding kyc {string}') do |eoi_args, kyc_args|
    @expression_of_interest = FactoryBot.build(:expression_of_interest, investment_opportunity: @investment_opportunity, investor: @investor, user: @investor.users.first)
    key_values(@expression_of_interest, eoi_args)
    @expression_of_interest.save!

    @kyc = FactoryBot.build(:investor_kyc, entity: @entity, investor: @investor, full_name: @expression_of_interest.investor_name)
    key_values(@kyc, kyc_args)
    @kyc.save

    @expression_of_interest.investor_kyc = @kyc
    @expression_of_interest.save!
  end
  
  When('a new investor should be created from the EOI') do
    @new_investor = Investor.last
    @new_investor.entity_id.should == @expression_of_interest.entity_id
    @new_investor.investor_name.should == @expression_of_interest.investor_name
    @new_investor.primary_email.should == @expression_of_interest.investor_email
    @new_investor.category.should == "LP"
  end