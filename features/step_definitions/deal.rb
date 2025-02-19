include CurrencyHelper

Given('I am at the deals page') do
  visit("/deals")
end

When('I click the last {string} link') do |args|
  all('a', text: args).last.click
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  ##sleep(2)
end

When('I create a new deal {string}') do |arg1|
  @deal = FactoryBot.build(:deal)
  key_values(@deal, arg1)
  click_on("New Deal")
  fill_in('deal_name', with: @deal.name)
  fill_in('deal_amount', with: @deal.amount)
  fill_in('deal_status', with: @deal.status)
  click_on("Save")
  sleep(3)

  kanban_board = KanbanBoard.first
  kanban_columns = kanban_board.kanban_columns.pluck(:name)
  kanban_columns.each { |column| expect(page.text).to(include(column)) }
end

When('I edit the deal {string}') do |arg1|
  key_values(@deal, arg1)

  click_on("Edit")

  fill_in('deal_name', with: @deal.name)
  fill_in('deal_amount', with: @deal.amount)
  fill_in('deal_status', with: @deal.status)

  click_on("Save")
  expect(page).to have_content("successfully")
  ##sleep(1)
end

When('I click on the Add Item and select any Investor and save') do
  # sleep(0.25)
  first('button', text: "Add Item").click
  # sleep(1)
  inv_entities = FactoryBot.create_list(:entity, 3, entity_type: "Investor")

  inv_entities.each do |inv_entity|
    @another_entity = inv_entity
    steps %(
      And another entity is an investor "category=Lead Investor" in entity
      )
    end
  select_investor_and_save(1, 'First Investment')
  select_investor_and_save(3, 'Second Investment')
  expect(page).to have_content("First Investment")
  expect(page).to have_content("Second Investment")
end

When('I click on a Kanban Card and edit the form') do
  deal_investor = DealInvestor.first
  find('h3', text: deal_investor.name).click
  ##sleep(0.5)
  click_link('Edit')
  ##sleep(0.25)
  fill_in('Tags', with: "Random, Tag")
  click_button('Save')
  sleep(1)
  first(".offcanvas-close").click
  expect(all(".kanban-card").first.text).to include("Random")
  expect(all(".kanban-card").first.text).to include("Tag")
end

When("I click on a Kanban Card's tags") do
  KanbanCardIndex.import!
  expect(all(".kanban-card").count).to(eq(2))
  click_link("Random")
  sleep(2)
  expect(all(".kanban-card").count).to(eq(1))
end

When("I move card from one column to another") do
  all(".move-to-next-column").first.click
  sleep(3)
  expect(KanbanCard.first.audits.last.audited_changes.keys).to(include("kanban_column_id"))
end

Then('an deal should be created') do
  @created = Deal.last
  @created.name.should
  @deal.name
  @created.amount.should
  @deal.amount
  @created.status.should
  @deal.status
  @deal = @created
end

Then('I should see the deal details on the details page') do
  visit(deal_path(@deal, grid_view: true))
  find_by_id('deal_tab').click
  expect(page).to have_content(@deal.name)
  expect(page).to have_content(money_to_currency(@deal.amount))
  expect(page).to have_content(@deal.status)
  # #sleep(10)
end

Then('I should see the deal in all deals page') do
  visit("/deals")
  expect(page).to have_content(@deal.name)
  expect(page).to have_content(money_to_currency(@deal.amount).scan(/\d+/).map(&:to_i)[0])
end

Given('I visit the deal details page') do
  ##sleep(5)
  @deal.reload
  visit(deal_path(@deal, grid_view: true))
end

Then('I should be able to change currency units') do
  ["Crores", "Lakhs", "Million"].each do |curr|
    select(curr, from: "currency_units")
    ##sleep(0.5)
    expect(page).to have_content(money_to_currency(@deal.amount, {units: curr}))
  end
end

Given('there exists a deal {string} for my company') do |arg1|
  @deal = FactoryBot.build(:deal)
  key_values(@deal, arg1)
  CreateDeal.wtf?(deal: @deal).success?.should
  puts "\n####Deal####\n"
  puts @deal.to_json
end

Given('when I start the deal') do
  click_on("Start Deal")
  ##sleep(1) # To allow all deal activities to be created by job
end

Then('the deal should be started') do
  @deal.reload
  @deal.start_date.should_not
  @deal.deal_activities.should_not.nil?
end

Given('given there is a deal {string} for the entity') do |arg1|
  @deal = FactoryBot.build(:deal, entity_id: @entity.id)
  key_values(@deal, arg1)
  CreateDeal.wtf?(deal: @deal).success?.should
  puts "\n####Deal####\n"
  puts @deal.to_json
end

Given('the deal is started') do
  @deal.start_deal
end

Given('I am {string} employee access to the deal') do |given|
  @access_right = AccessRight.create(entity_id: @deal.entity_id, owner: @deal, user_id: @user.id) if %w[given yes].include?(given)
  @user.reload
end

Given('I have {string} access to the deal') do |should|
  Pundit.policy(@user, @deal).show?.should == (should == "true")
end

Given('I should not have access to the deal') do
  Pundit.policy(@user, @deal).show?.should == false
end

Given('I have {string} access to the deal data room') do |arg|
  Pundit.policy(@user, @deal.data_room_folder).show?.to_s.should == arg
end

Then('another user {string} have access to the deal data room') do |arg|
  Pundit.policy(@another_user, @deal.data_room_folder).show?.to_s.should == arg
end

Given('another user {string} have access to the deal') do |arg|
  Pundit.policy(@another_user, @deal).show?.to_s.should == arg
end

Given('another entity is an investor {string} in entity') do |arg|
  random_pan = Faker::Alphanumeric.alphanumeric(number: 10, min_alpha: 3)
  # @entity = FactoryBot.create(:entity, entity_type: "Startup")
  @investor = Investor.new(investor_name: @another_entity.name, investor_entity: @another_entity, entity: @entity, pan: random_pan, primary_email: @another_entity.primary_email)
  key_values(@investor, arg)
  @investor.save!
  puts "\n####Investor####\n"
  puts @investor.to_json
end

Given('another entity is a deal_investor {string} in the deal') do |arg|
  @deal_investor = DealInvestor.new(investor: @investor, entity: @entity, deal: @deal)
  key_values(@deal_investor, arg)
  @deal_investor.save!
  puts "\n####Deal Investor####\n"
  puts @deal_investor.to_json
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

Given('investor has access right {string} in the deal') do |arg1|
  @access_right = AccessRight.new(owner: @deal, entity: @entity)
  key_values(@access_right, arg1)
  @access_right.save!
  puts "\n####Access Right####\n"
  puts @access_right.to_json
end

############################################################################
############################################################################
#######################  Investor related test steps #############################
############################################################################
############################################################################

Given('there are {string} exisiting deals {string} with another firm in the startups') do |count, _args|
  @another_entity = FactoryBot.create(:entity, entity_type: "Investor")

  Entity.startups.each do |company|
    @investor = FactoryBot.create(:investor, investor_entity: @another_entity, entity: company)
    (1..count.to_i).each do
      deal = FactoryBot.build(:deal, entity: company)
      CreateDeal.wtf?(deal:).success?.should

      begin
        FactoryBot.create(:deal_investor, investor: @investor, entity: company, deal:)
      rescue Exception => e
        puts deal.entity.folders.collect(&:full_path)
        puts deal.to_json
        raise e
      end
    end
  end
end

Given('there are {string} exisiting deals {string} with my firm in the startups') do |count, _args|
  Entity.startups.each do |company|
    (1..count.to_i).each do
      deal = FactoryBot.create(:deal, entity: company, name: Faker::Company.bs)
      puts "\n####Deal####\n"
      ap deal

      inv = deal.entity.investors.where(investor_name: @investor.investor_name).first
      di = FactoryBot.create(:deal_investor, investor: inv, entity: company, deal:)
      puts "\n####Deal Investor####\n"
      ap di
    end
  end
end

Given('I am at the deal_investors page') do
  visit(deal_investors_path)
end

Then('I should not see the deals of the company') do
  DealInvestor.find_each do |di|
    within("#deal_investors") do
      expect(page).to have_no_content(di.deal_name)
      expect(page).to have_no_content(di.investor_name)
    end
  end
end

Then('I should see the deals of the company') do
  DealInvestor.where(investor_entity_id: @entity.id).find_each do |di|
    expect(page).to have_content(di.deal_name)
  end
end

Then('I should not see the deal cards of the company') do
  DealInvestor.find_each do |di|
    expect(page).to have_no_content(di.deal.name)
  end
end

Then('I should see the deal cards of the company') do

  DealInvestor.where(investor_entity_id: @entity.id).find_each do |di|
    expect(page).to have_content(di.deal.name)
    expect(page).to have_content(di.deal.status)
    expect(page).to have_content("Overview")
    expect(page).to have_content("Queries")
  end
end

Given('I have access to all deals') do
  DealInvestor.where(investor_entity_id: @entity.id).find_each do |di|
    InvestorAccess.create!(investor: di.investor, user: @user,
                           first_name: @user.first_name,
                           last_name: @user.last_name,
                           email: @user.email, approved: true,
                           entity_id: di.entity_id)

    ar = AccessRight.create(owner: di, access_type: "DealInvestor",
                            entity: di.entity, access_to_investor_id: di.investor_id)

    puts "\n####Access Right####\n"
    puts ar.to_json
  end

  puts "\n####DealInvestor.for_investor####\n"
  puts DealInvestor.for_investor(@user).to_json
end

Given('the investors are added to the deal') do
  @user.entity.investors.each do |inv|
    ar = AccessRight.create(owner: @deal, access_type: "Deal",
                            access_to_investor_id: inv.id, entity: @user.entity)

    puts "\n####Granted Access####\n"
    puts ar.to_json
  end
end

Then('the deal data room should be setup') do
  @deal.reload
  puts "\n####Data Room####\n"
  puts @deal.data_room_folder.to_json
  @deal.data_room_folder.should_not
  @deal.data_room_folder.name.should
  @deal.data_room_folder.full_path.should == "/Deals/#{@deal.name}/Overview"
end

def select_investor_and_save(investor_id, tags)
  ##sleep(2)
  investor = Investor.find(investor_id)
  first('button', text: "Add Item").click
  sleep(1)
  select(investor.investor_name, from: "deal_investor_investor_id")
  input_field = find_by_id('deal_investor_tags')
  input_field.set(tags)
  sleep(0.5)
  click_button('Save')
  sleep(2)
  # binding.pry
  expect(page).to have_content(investor.investor_name)
end

When('I click on a Kanban Card') do
  sleep(1)
  @deal_investor = DealInvestor.last
  find('h3', text: @deal_investor.name).click
end

Then('The offcanvas opens') do
  # find('#offcanvas_DealInvestor83Activity1066')
  expect(page).to have_content(@deal_investor.name)
  # below contents are only on offcanvas
  expect(page).to have_content(@deal_investor.deal.name)
  expect(page).to have_content("Deal")
  expect(page).to have_content("Status")
  expect(page).to have_content("Deal Lead")
  expect(page).to have_content("Source")
end

When('I click on the delete button on offcanvas') do
  click_on('Delete')
  ##sleep(0.5)
  click_on("Proceed")
  ##sleep(5)
end

Then('The card is deleted from the kanban board') do
  expect(page).to have_no_content(@deal_investor.name)
  expect(all(".kanban-card").count).to(eq(1))
end

When('I click on the Add Item and select previously deleted Investor and save') do
  visit(page.current_url)
  @inv = Investor.find 1
  select_investor_by_name_and_save(@inv.investor_name, "some tag")
  ##sleep(1)
end

def select_investor_by_name_and_save(name, tags)
  ##sleep(2)
  first('button', text: "Add Item").click
  ##sleep(1)
  select(name, from: "deal_investor_investor_id")
  input_field = find_by_id('deal_investor_tags')
  input_field.set(tags)
  ##sleep(0.5)
  click_button('Save')
  sleep(5)
end

When('I click on the action dropdown and create a Kanban Column') do
  find(".column-add").click
  ##sleep(0.5)
  find_by_id('kanban_column_name').set('New Column')
  click_button('Save')
  sleep(1)
  expect(page.text).to(include('New Column'))
end

Then('I should see the error "{string}"') do |string|
  expect(page).to have_content(string)
end

When('I click on the action dropdown and select the same Investor and save') do
  inv_entities = FactoryBot.create_list(:entity, 3, entity_type: "Investor")

  inv_entities.each do |inv_entity|
    @another_entity = inv_entity
    steps %(
      And another entity is an investor "category=Lead Investor" in entity
      )
    end
  select_investor_and_save(2, 'First Investment')
  select_investor_and_save(2, 'New Investment')
end

When('I click on the action dropdown and dont select any Investor and save') do
  first('button', text: "Add Item").click
  ##sleep(1)
  click_button('Save')
  sleep(1)
end

Then('i click on the details button') do
  within("#card_offcanvas_turbo_frame") do
    @new_window = window_opened_by { click_on("Details") }
  end
end

Then('I should see the details of the deal investor') do
  within_window @new_window do
    # Confirm the content in the new tab
    expect(page).to have_content(@deal_investor.name)
    expect(page).to have_content(@deal_investor.deal.name)
    expect(page).to have_content(@deal_investor.entity.name)
    expect(page).to have_content(@deal_investor.investor_name)
    expect(page).to have_content("Source")
    expect(page).to have_content("Deal Lead")
    expect(page).to have_content("Status")
  end

  # Optionally close the new window and switch back to the original window
  @new_window.close
  switch_to_window(windows.first)
end

When('I edit the deal "card_view_attrs={string}"') do |string|
  update_deal_investors(@deal)
  # find dropdown with class dropdown and click
  dropdown = all(".dropdown").first
  dropdown.click
  #sleep(0.5)
  dropdown = all(".dropdown").last
  xpath = "/html/body/div[2]/div[1]/div/div/turbo-frame/div[2]/div/div"
  element = find(:xpath, xpath)
  element.click
  click_on("Edit")
  #sleep(0.5)
  fill_in('Tags', with: "Deal Tag")
  # find('.select2-selection--multiple').click

  # string.split(",").each do |attr|
  #   attr = attr.strip
  #   # Find the search field within the dropdown and enter 'Status'
  #   find('.select2-search__field').set("#{attr}")
  #   find('li.select2-results__option', text: "#{attr}").click
  # end
  click_on("Save")
  sleep(2)
end


Then('deal and cards should be updated') do
  visit current_url
  element = all('.show_details_link').last
  element.click
  #sleep(0.5)
  click_on("Deal")
  #sleep(0.5)
  expect(page).to have_content("Deal Tag")
  expect(page).to have_content(@deal.reload.card_view_attrs&.map(&:titleize)&.join(", "))
end

When('i click on deal details i should see the tabs "{string}"') do |string|
  string.split(",").each do |tab|
    tab = tab.strip
    p "clicking on tab #{tab}"
    expect(page).to have_content(tab)
    click_on(tab)
    #sleep(0.5)
    if tab == "Access Rights"
      expect(page).to have_content("Grant Access")
    end
    if tab == "Deal"
      expect(page).to have_content("#{@deal.entity.name}")
      expect(page).to have_content("Card View Attributes")
      expect(page).to have_content("Start Date")
    end
  end
end

When('i should see be able to edit the deal from deal tab') do
  click_on("Deal")
  #sleep(0.5)
  element = find("#deal_show")
  within(element) do
    click_on("Edit")
    #sleep(1)
    # check if the form is visible
  end

  fill_in('deal_name', with: "New Deal Name")
  fill_in('deal_status', with: "New Status")
  click_on("Save")
  #sleep(1)
  element = all('.show_details_link').last
  element.click
  #sleep(0.5)
  click_on("Deal")
  #sleep(0.5)
  expect(page).to have_content("New Deal Name")
  expect(page).to have_content("New Status")
end

def update_deal_investors(deal)
  deal_investors_temp = []
  deal.deal_investors.count.times do |i|
    deal_investors_temp << FactoryBot.build(:deal_investor, deal: deal)
  end
  deal.deal_investors.each_with_index do |di, idx|
    di.update(pre_money_valuation: deal_investors_temp[idx].pre_money_valuation, tier: deal_investors_temp[idx].tier, status: deal_investors_temp[idx].status, deal_lead: deal_investors_temp[idx].deal_lead)
  end
end

Given('I view the deal details') do
  visit(deal_path(@deal))
  element = all('.show_details_link').last
  element.click
  #sleep(0.5)
end

Given('I add widgets for the deal') do
  click_on("Widgets")
  click_on("New Widget")

  fill_in('ci_widget_title', with: "Left Widget")
  select("Left", from: "ci_widget_image_placement")
  details_top_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[3]/trix-editor")
  details_top_element.set("Left Widget Intro")
  details_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[4]/trix-editor")
  details_element.set("Left Widget Details")
  attach_file('files[]', File.absolute_path("./public/img/logo_big.png"), make_visible: true)
  sleep(0.5)
  click_on("Save")
  expect(page).to have_content("successfully")

  visit(deal_path(@deal))
  element = all('.show_details_link').last
  element.click
  click_on("Widgets")
  click_on("New Widget")
  fill_in('ci_widget_title', with: "Center Widget")
  select("Center", from: "ci_widget_image_placement")
  details_top_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[3]/trix-editor")
  details_top_element.set("Center Widget Intro")
  details_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[4]/trix-editor")
  details_element.set("Center Widget Details")
  attach_file('files[]', File.absolute_path("./public/img/logo_big.png"), make_visible: true)
  sleep(0.5)
  click_on("Save")
  expect(page).to have_content("successfully")

  visit(deal_path(@deal))
  element = all('.show_details_link').last
  element.click
  click_on("Widgets")
  click_on("New Widget")
  fill_in('ci_widget_title', with: "Right Widget")
  select("Right", from: "ci_widget_image_placement")
  details_top_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[3]/trix-editor")
  details_top_element.set("Right Widget Intro")
  details_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[4]/trix-editor")
  details_element.set("Right Widget Details")
  attach_file('files[]', File.absolute_path("./public/img/logo_big.png"), make_visible: true)
  sleep(0.5)
  click_on("Save")
  expect(page).to have_content("successfully")
end

Given('I add track record for the deal') do
  visit(deal_path(@deal))
  element = all('.show_details_link').last
  element.click
  click_on("Track Record")
  click_on("New Track Record")
  fill_in('ci_track_record_name', with: "Test Track Record")
  fill_in('ci_track_record_prefix', with: "good")
  fill_in('ci_track_record_value', with: "250000")
  fill_in('ci_track_record_suffix', with: "bad")
  fill_in('ci_track_record_details', with: "Track record details")
  click_on("Save")
  expect(page).to have_content("successfully")
  switch_to_window windows.first
end

When('I go to deal preview') do
  visit(deal_path(@deal))
  click_on("Overview")
  switch_to_window windows.last
end

Then('I can see the deal preview details') do
  @deal.ci_widgets.each do |widget|
    expect(page).to have_content(widget.title)
    expect(page).to have_content(widget.details_top.gsub(/<\/?div>/, ''))
    expect(page).to have_content(widget.details.gsub(/<\/?div>/, ''))
  end
  @deal.ci_track_records.each do |track_record|
    expect(page).to have_content(track_record.name)
    expect(page).to have_content(track_record.prefix)
    expect(page).to have_content(track_record.value)
    expect(page).to have_content(track_record.suffix)
    expect(page).to have_content(track_record.details.gsub(/<\/?div>/, ''))
  end
end


Given('I click on the Add Item and create a new Stakeholder {string} and save') do |arg|
  @inv = FactoryBot.build(:investor)
  key_values(@inv, arg)
  first('button', text: "Add Item").click
  #sleep(0.25)
  puts "\n####Creating New Stakeholder - #{@inv.investor_name} with #{@inv.primary_email}####\n"

  click_on("New Stakeholder")
  fill_in('investor_investor_name', with: @inv.investor_name)
  select("LP", from: "investor_category")
  fill_in('investor_primary_email', with: @inv.primary_email)
  click_on("Save")
  sleep(3)
  visit(current_url)
end

Given('I click on the Add Item and select {string} Investor and save') do |investor_name|
  puts "\n####Creating New Deal Investor - #{investor_name}####\n"
  select_investor_name_and_save(investor_name, Faker::Company.profession)
  visit(current_url)
  @deal_investor = DealInvestor.last
end

def select_investor_name_and_save(investor_name, tags)
  first('button', text: "Add Item").click
  #sleep(1)
  select(investor_name, from: "deal_investor_investor_id")
  input_field = find_by_id('deal_investor_tags')
  input_field.set(tags) if tags.present?
  #sleep(0.5)
  click_button('Save')
  sleep(2)
end

Given('I give deal access to {string}') do |investor_name|
  visit(deal_path(@deal))
  element = all('.show_details_link').last
  element.click
  click_on("Access Rights")
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  puts "\n####Granting Deal Access to #{investor_name}####\n"
  #sleep(2)
  click_on("Grant Access")
  find('.select2-selection--multiple').click
  find('.select2-search__field').set(investor_name)
  find('li.select2-results__option', text: investor_name).click
  click_on("Save")
  sleep(1)
end

When('I go to the deal access overview') do
  @deal = Deal.last
  path = consolidated_access_rights_deal_path(id: @deal.id)
  visit(path)
end

Then('I should see the {string} {string} access') do |number, access_type|
  expect(page).to have_content("#{access_type.titleize} access granted by").exactly(number.to_i).times
end

Given('I give {string} access to {string} from the deal access overview') do |access_type, investor_name|
  puts "\n####Granting #{access_type} Access from Access Overview to #{investor_name}####\n"

  visit(consolidated_access_rights_deal_path(id: @deal.id))
  #sleep(2)
  click_on("Grant Access")
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  button_text = access_type.titleize
  button_text = "Document Folder" if access_type == "folder"
  click_on("Grant #{button_text.titleize} Access")
  #sleep(0.3)
  find('.select2-selection--multiple').click
  find('.select2-search__field').set(investor_name)
  find('li.select2-results__option', text: investor_name).click

  check("access_right_cascade") if access_type == "folder"

  click_on("Save")
  sleep(1)
end

Given('I delete {string} access to {string} from the deal access overview') do |access_type, investor_name|
  puts "\n####Deleting #{access_type} Access from Access Overview of #{investor_name}####\n"
  visit(consolidated_access_rights_deal_path(id: @deal.id))
  first('button', text: "Delete #{access_type.titleize} Access").click
  click_on("Proceed")
end

Given('Investor {string} has a user with email {string}') do |investor_name, email|
  @investor = Investor.find_by(investor_name: investor_name)
  @user = FactoryBot.create(:user, email: email, entity: @investor.investor_entity)
  @investor_access = InvestorAccess.new(entity: @investor.entity, investor: @investor,
                                        first_name: @user.first_name, last_name: @user.last_name,
                                        email: @user.email, granter: User.first, approved: true)
  @investor_access.save!
  puts "\n####Investor Access####\n"
  puts @investor_access.to_json
end

Given('user {string} has deals enabled') do |email|
  @user ||= User.find_by(email: email)
  @user.entity.permissions.set(:enable_deals)
  @user.entity.save
  @user.permissions.set(:enable_deals)
  @user.save
end

When('I go to the deal investors page') do
  visit(deal_investors_path)
end

Then('I should see the deal card {string}') do |deal_name|
  expect(page).to have_content(@deal.name)
  expect(page).to have_content("Overview")
  expect(page).to have_content("Queries")
end

When('I go to investor deal overview') do
  @deal ||= Deal.last
  visit(overview_deal_path(@deal))
end

When('I click Deal Documents in the overview') do
  all('a', text: "Documents").last.click
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
end

Then('I should see the deal documents') do
  sleep(1)
  temp_url = current_url+"&&no_folders=true"
  visit(temp_url)
  sleep(1)
  expect(page).to have_content("Documents: Deal Documents")
  @deal.deal_documents_folder.documents.each do |doc|
    puts "Checking for #{doc.name}"
    puts doc.access_rights.map{|ar| ar.investor.investor_name}
    puts @user.entity.name
    expect(page).to have_content(doc.name)
  end
end

Then('I should not see the deal documents') do
  #sleep(1)
  expect(page).not_to have_content("Documents: Deal Documents")
end

When('I click on deals document') do
  @deal_document = @deal.deal_documents_folder.documents.last
  click_on(@deal_document.name)
end

Then('I should see the document details') do
  expect(page).to have_content("Viewing: #{@deal_document.name}")
end

Given('User {string} deals folder access is removed') do |email|
  @user ||= User.find_by(email: email)
  @deal.deal_documents_folder.access_rights.where(access_to_investor_id: @investor.id).destroy_all
end

Then('I should see {string}') do |message|
  expect(page).to have_content(message)
end

Given('User {string} deals access is removed') do |email|
  @user ||= User.find_by(email: email)
  @deal.access_rights.where(access_to_investor_id: @investor.id).destroy_all
end

Then('I cannot see the deal card {string}') do |deal_name|
  expect(page).not_to have_content(@deal.name)
  expect(page).not_to have_content("Overview")
  expect(page).not_to have_content("Queries")
end
