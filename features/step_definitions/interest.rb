  Then('I should see only relevant sales details') do
    find(".show_details_link").click
    expect(page).to have_content(@sale.name)
    # expect(page).to have_content(@sale.start_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(@sale.end_date.strftime("%d/%m/%Y"))
    if @sale.price_type == "Fixed Price"
      expect(page).to have_content(@sale.final_price)
    else
      expect(page).to have_content(@sale.min_price)
      expect(page).to have_content(@sale.max_price)
    end
    expect(page).to have_no_selector('tr#percent_allowed')

  end
  
  Then('I should not see the private files') do
    expect(page).to have_no_content("Private Files")
  end
  
  Then('when I create an interest {string}') do |args|
    @interest = Interest.new
    key_values(@interest, args)
    click_on("New Interest")
    fill_in("interest_buyer_entity_name", with: @interest.buyer_entity_name)
    fill_in("interest_quantity", with: @interest.quantity)
    fill_in("interest_price", with: @interest.price) unless @sale.price_type == "Fixed Price"
    click_on("Save")
    expect(page).to have_content("successfull")
  end

  Then('when the interest sale is finalized') do
    @created_interest.secondary_sale.finalized = true
    @created_interest.secondary_sale.lock_allocations = true    
    @created_interest.secondary_sale.final_price = 150
    @created_interest.secondary_sale.save!
    @created_interest.reload
  end

  Then('when the interest is shortlisted') do
    InterestShortList.call(interest: @created_interest, short_listed_status: Interest::STATUS_SHORT_LISTED, current_user: @created_interest.entity.employees.sample).success?.should == true
  end
  
  
  Then('I edit the interest {string}') do |args|
    visit (edit_interest_url(@created_interest))
    @interest = FactoryBot.build(:interest, quantity: @created_interest.quantity, price: @created_interest.price)    
    key_values(@interest, args)

    unless @created_interest.short_listed
      fill_in("interest_buyer_entity_name", with: @interest.buyer_entity_name)
    end
    click_on("Next")
    fill_in("interest_address", with: @interest.address)
    fill_in("interest_contact_name", with: @interest.contact_name)
    # fill_in("interest_email", with: @interest.email)
    fill_in("interest_PAN", with: @interest.PAN)
    fill_in("interest_city", with: @interest.city)
    fill_in("interest_demat", with: @interest.demat)

    click_on("Save")
  end
  

  Given('an interest {string} from some entity {string}') do |int_args, entity_args|
    @buyer_entity = FactoryBot.build(:entity)
    key_values(@buyer_entity, entity_args)
    @buyer_entity.save!
    @buyer_user = FactoryBot.create(:user, entity: @buyer_entity)

    investor = FactoryBot.create(:investor, entity: @entity, investor_entity: @buyer_entity, category: "Co-Investor") 
    @interest = Interest.new(user: @buyer_user, investor: investor, 
            secondary_sale: @sale, entity: @sale.entity)
    key_values(@interest, int_args)
    

    puts "min_price #{@interest.price > @sale.min_price}"
    puts "max_price #{@interest.price < @sale.max_price}"
    puts @interest.to_json

    InterestCreate.call(interest: @interest).success?.should == true

  end
  

  When('I visit the interest details page') do
    @interest ||= Interest.last
    visit(interest_path(@interest))
  end
  
  
  Then('I should see the interest details') do
    #sleep(1)
    @created_interest = Interest.last

    @interest ||= @created_interest # If the interest was not created thru UI in the tests 
    
    puts "\n####Created Interest####\n"
    puts @created_interest.to_json

    expect(page).to have_content(@interest.price)
    expect(page).to have_content(@interest.quantity)
    # if @user.entity_id == @created_interest.interest_entity_id || @created_interest.escrow_deposited
    if @created_interest.buyer_entity_name.present?
        expect(page).to have_content(@created_interest.buyer_entity_name) 
    elsif @created_interest.user 
        expect(page).to have_content(@created_interest.user.full_name) 
    end
    expect(page).to have_content(@created_interest.interest_entity.name)
    # else
    #     expect(page).to have_no_content(@created_interest.user.full_name)
    #     expect(page).to have_no_content(@created_interest.interest_entity.name)
    #     expect(page).to have_content(ENV["OBFUSCATION"])
    # end
    # expect(page).to have_content(@created_interest.entity.name)
    
    within("#short_listed") do
        expect(page).to have_content(@created_interest.short_listed_status.humanize)
    end
    within("#verified") do
        label = @created_interest.verified ? "Yes" : "No"
        expect(page).to have_content(label)
    end

    if @created_interest.secondary_sale.finalized
      expect(page).to have_content(@created_interest.buyer_entity_name)
      expect(page).to have_content(@created_interest.address)
      expect(page).to have_content(@created_interest.contact_name)
      expect(page).to have_content(@created_interest.email)
      expect(page).to have_content(@created_interest.PAN)
    end

    @interest = @created_interest
  end
  
  Then('I {string} the interest') do |action|
    within("#interest_#{@created_interest.id}") do
      click_on(action)
    end
  end

  Then('the interest should be shortlisted') do
    #sleep(1)
    @created_interest.reload
    @created_interest.short_listed.should == true
    within("#short_listed") do
        expect(page).to have_content("Yes")
    end
  end
  
  
Given('given I upload an interests file {string}') do |file_name|
  @import_offer_file_name = file_name
  @existing_user_count = User.count
  visit(secondary_sale_path(@sale))
  sleep(2)
  # click_on("Interests")
  within("#interest_buttons") do
    click_on("Upload Interests")
  end
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  sleep(2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  # sleep(4)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep(5)

  ImportUpload.last.failed_row_count.should == 0

  
end