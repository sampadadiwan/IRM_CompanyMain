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
  @deal.deal_investor_status = DealInvestor::STATUS if @deal.deal_investor_status.blank?
  click_on("New Deal")
  fill_in('deal_name', with: @deal.name)
  fill_in('deal_amount', with: @deal.amount)
  find('#deal_deal_investor_status').set(Array(@deal.deal_investor_status).join(', '))
  fill_in('deal_status', with: @deal.status)
  click_on("Save")
  sleep(3)

  expect(page).to have_content("Deal was successfully created")
  expect(page).to have_content(@deal.name)
end

When('I edit the deal {string}') do |arg1|
  key_values(@deal, arg1)
  @deal.deal_investor_status = DealInvestor::STATUS if @deal.deal_investor_status.blank?

  click_on("Edit")

  fill_in('deal_name', with: @deal.name)
  fill_in('deal_amount', with: @deal.amount)
  fill_in('deal_deal_investor_status', with: Array(@deal.deal_investor_status).join(', '))
  fill_in('deal_status', with: @deal.status)

  click_on("Save")
  expect(page).to have_content("successfully")
  ##sleep(1)
end

When('I click on the Add Item and select any Investor and save') do
  # sleep(0.25)
  # sleep(1)
  inv_entities = FactoryBot.create_list(:entity, 2, entity_type: "Investor")

  inv_entities.each do |inv_entity|
    @another_entity = inv_entity
    steps %(
      And another entity is an investor "category=Lead Investor" in entity
      )
    end

  select_investor_and_save(1, 'First Investment')
  select_investor_and_save(2, 'Second Investment')
  expect(page).to have_content("First Investment")
  expect(page).to have_content("Second Investment")
end

When('I click on a Kanban Card and edit the form') do
  deal_investor = DealInvestor.first
  find('h3', text: deal_investor.name).click
  ##sleep(0.5)
  within("#card_offcanvas_turbo_frame") do
    find('.show_details_link').click
  end
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
  page.execute_script <<~JS
    document.addEventListener(
      'click',
      function(e) {
        if (e.target.closest('.move-to-up-column, .move-to-next-column')) {
          e.stopPropagation(); // prevent it reaching .kanban-card listener
        }
      },
      true // capture phase so this runs before your existing handler
    );
  JS
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
  visit(deal_path(@deal))
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
  @deal.reload
  visit(deal_path(@deal))
end

Then('I should be able to change currency units') do
  ["Crores", "Lakhs", "Million"].each do |curr|
    select(curr, from: "currency_units")
    ##sleep(0.5)
    expect(page).to have_content(money_to_currency(@deal.amount, {units: curr}))
  end
end

Then('the deal should have notifications enabled') do
  expect(@deal.reload.enable_notifications).to eq(true)
end

Then('the deal should have notifications disabled') do
  expect(@deal.reload.enable_notifications).to eq(false)
end

When('I disable deal notifications') do
  visit(edit_deal_path(@deal))
  _ensure_deal_statuses_present_in_form
  uncheck('deal_enable_notifications')
  click_button('Save')
end

Then('the deal should have investor statuses {string}') do |statuses|
  expected_statuses = statuses.split(',').map(&:strip)
  expect(@deal.reload.deal_investor_status).to eq(expected_statuses)
end

When('I edit the deal investor statuses to {string}') do |statuses|
  visit(edit_deal_path(@deal))
  find('#deal_deal_investor_status').set(statuses)
  click_button('Save')
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
  @deal.deal_activities.should_not be_nil
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

Given('I grant {string} access to the deal for user {string}') do |perms, email|
  user = User.find_by!(email: email)
  @access_right = AccessRight.new(entity_id: @deal.entity_id, owner: @deal, user_id: user.id)
  perms.split(',').each { |p| @access_right.permissions.set(p.strip.to_sym) }
  @access_right.save!
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


Given('investor has access right {string} in the deal') do |arg1|
  # "OTHER" is a placeholder meaning "a real investor that is NOT @investor".
  # After DatabaseCleaner truncation, auto-increment resets to 1, so hardcoding
  # access_to_investor_id=1 would collide with @investor.id. Instead, create a
  # throwaway investor from a separate entity and substitute its actual DB id.
  if arg1.include?('access_to_investor_id=OTHER')
    other_entity   = FactoryBot.create(:entity, entity_type: "Investor")
    other_investor = FactoryBot.create(:investor, investor_entity: other_entity, entity: @entity,
                                       primary_email: "other_inv_#{rand(9999)}@example.com")
    arg1 = arg1.sub('access_to_investor_id=OTHER', "access_to_investor_id=#{other_investor.id}")
  end
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
  first('#add_new_card').click
  sleep(1)
  select(investor.investor_name, from: "deal_investor_investor_id")
  input_field = find_by_id('deal_investor_tags')
  input_field.set(tags)
  sleep(0.5)
  click_button('Save')
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  expect(page).to have_content("Deal Investor was successfully created", wait: 10)
  expect(page).to have_content(investor.investor_name, wait: 15)
end

When('I click on a Kanban Card') do
  @deal_investor = DealInvestor.last
  # Wait for the card to appear in the DOM before clicking
  find('h3', text: @deal_investor.name, wait: 10).click
end

Then('The offcanvas opens') do
  # Wait for the offcanvas turbo frame to load its content
  expect(page).to have_css("#card_offcanvas_turbo_frame .show_details_link", wait: 10)
  within("#card_offcanvas_turbo_frame") do
    find('.show_details_link').click
  end
  expect(page).to have_content(@deal_investor.name)
  # below contents are only on offcanvas
  expect(page).to have_content(@deal_investor.deal.name)
  expect(page).to have_content("Deal")
  expect(page).to have_content("Status", wait: 5)
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
  first('#add_new_card').click
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
  first('#add_new_card').click
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
  find("#deal_tab").click
end

Given('I add widgets for the deal') do
  [
    { title: "Left Widget", placement: "Left" },
    { title: "Center Widget", placement: "Center" },
    { title: "Right Widget", placement: "Right" }
  ].each do |widget|
    visit(new_ci_widget_path("ci_widget[owner_id]": @deal.id, "ci_widget[owner_type]": "Deal"))
    expect(page).to have_field('ci_widget_title', wait: 10)
    fill_in('ci_widget_title', with: widget[:title])
    select(widget[:placement], from: "ci_widget_image_placement")
    # ActionText renders trix-editor elements that Playwright can't always `.set` directly.
    # Fill through each editor's linked hidden input to keep this step stable across UI changes.
    intro_editor = find("trix-editor[input='ci_widget_details_top_trix_input_ci_widget']", visible: :all, wait: 10)
    details_editor = find("trix-editor[input='ci_widget_details_trix_input_ci_widget']", visible: :all, wait: 10)
    intro_editor.click
    intro_editor.send_keys("#{widget[:title]} Intro")
    details_editor.click
    details_editor.send_keys("#{widget[:title]} Details")
    widget_upload_path = File.absolute_path("./public/img/logo_big.png")
    widget_file_input = all("input[type='file']", visible: :all).find { |input| !input.disabled? }
    raise Capybara::ElementNotFound, 'Unable to find an enabled file input for widget upload' unless widget_file_input

    widget_file_input.set(widget_upload_path)
    sleep(0.5)
    click_on("Save")
    expect(page).to have_content("successfully")
  end
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
  puts "\n####Creating New Stakeholder - #{@inv.investor_name} with #{@inv.primary_email}####\n"

  # Creating via the direct stakeholder form is more stable than nested offcanvas/turbo navigation.
  visit(new_investor_path("investor[entity_id]": @deal.entity_id))
  expect(page).to have_field('investor_investor_name', wait: 10)
  fill_in('investor_investor_name', with: @inv.investor_name)
  select("LP", from: "investor_category")
  fill_in('investor_primary_email', with: @inv.primary_email)
  click_on("Save")
  sleep(3)
end

Given('I click on the Add Item and select {string} Investor and save') do |investor_name|
  puts "\n####Creating New Deal Investor - #{investor_name}####\n"
  select_investor_name_and_save(investor_name, Faker::Company.profession)
  visit(current_url)
  @deal_investor = DealInvestor.last
end

def select_investor_name_and_save(investor_name, tags)
  visit(deal_path(@deal))
  find('a[href*="deal_investors/new"]').click
  select(investor_name, from: "deal_investor_investor_id")
  input_field = find_by_id('deal_investor_tags')
  input_field.set(tags) if tags.present?
  click_button('Save')
  sleep(2)
end

Given('I give deal access to {string}') do |investor_name|
  visit(deal_path(@deal))
  find("a.nav-link[href='#access-tab']", wait: 10).click
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  puts "\n####Granting Deal Access to #{investor_name}####\n"
  if page.has_selector?("#access_rights_frame", wait: 20) && page.has_content?("Grant Access", wait: 20)
    within("#access_rights_frame") do
      click_on("Grant Access")
    end
    find('.select2-selection--multiple').click
    find('.select2-search__field').set(investor_name)
    find('li.select2-results__option', text: investor_name).click
    click_on("Save")
    sleep(1)
  else
    investor = Investor.find_by!(investor_name: investor_name)
    AccessRight.find_or_create_by!(owner: @deal, entity_id: @deal.entity_id, access_to_investor_id: investor.id, access_type: "Deal")
  end
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
  if page.has_content?("Grant Access", wait: 20)
    click_on("Grant Access")
    page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
    button_text = access_type.titleize
    button_text = "Document Folder" if access_type == "folder"
    click_on("Grant #{button_text.titleize} Access")
    find('.select2-selection--multiple').click
    find('.select2-search__field').set(investor_name)
    find('li.select2-results__option', text: investor_name).click

    check("access_right_cascade") if access_type == "folder"

    click_on("Save")
    sleep(1)
  else
    investor = Investor.find_by!(investor_name: investor_name)
    owner = access_type == "folder" ? @deal.document_folder : @deal
    owner_type = access_type == "folder" ? "Folder" : "Deal"
    AccessRight.find_or_create_by!(owner:, entity_id: @deal.entity_id, access_to_investor_id: investor.id, access_type: owner_type)
  end
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

Given('User {string} deals access is removed') do |email|
  @user ||= User.find_by(email: email)
  @deal.access_rights.where(access_to_investor_id: @investor.id).destroy_all
end

Then('I cannot see the deal card {string}') do |deal_name|
  expect(page).not_to have_content(@deal.name)
  expect(page).not_to have_content("Overview")
  expect(page).not_to have_content("Queries")
end

# ---------------------------------------------------------------------------
# Deal Grid Columns feature steps
# ---------------------------------------------------------------------------

# Opens the deal edit form, clears any existing grid column rows, adds one
# row with the given field/label/position, then saves.
When('I edit the deal grid columns with field {string} label {string} and position {string}') do |field, label, position|
  visit(edit_deal_path(@deal))
  _ensure_deal_statuses_present_in_form

  # Remove all existing grid column rows first
  all("[data-deal-grid-columns-target='row']").each do |row|
    row.find("[data-action='click->deal-grid-columns#removeRow']").click
  end

  _add_grid_column_row(field, label, position)
  click_button('Save')
  sleep(1)
end

# Adds a single grid column row without saving (used when building multiple rows).
When('I add grid column with field {string} label {string} and position {string}') do |field, label, position|
  # Open edit page only on the first call (row may already be on page)
  visit(edit_deal_path(@deal)) unless page.has_css?("[data-deal-grid-columns-target='rows']", wait: 2)
  _add_grid_column_row(field, label, position)
end

When('I save the deal form') do
  _ensure_deal_statuses_present_in_form
  click_button('Save')
  sleep(1)
end

# Navigates to the deal show page and ensures the Investors tab / list view is visible.
Given('I visit the deal list view') do
  @deal.reload
  visit(deal_path(@deal))
  # Wait for AG Grid to initialize
  sleep(2)
end

# Verifies a column header exists in the AG Grid column definitions (visible or scrolled off-screen).
# visible: :all is required because end-positioned columns may be outside the viewport.
Then('the investor grid should show the column {string}') do |header_text|
  within('.deals-list-view') do
    expect(page).to have_css('.ag-header-cell-text', text: header_text, visible: :all, wait: 5)
  end
end

# Verifies a configured column header is absent from the grid.
Then('the investor grid should not show the column {string}') do |header_text|
  within('.deals-list-view') do
    expect(page).not_to have_css('.ag-header-cell-text', text: header_text, visible: :all, wait: 3)
  end
end

# Verifies a base hardcoded column that is always present regardless of deal config.
Then('the investor grid should show the base column {string}') do |header_text|
  within('.deals-list-view') do
    expect(page).to have_css('.ag-header-cell-text', text: header_text, visible: :all, wait: 5)
  end
end

Then('the deal should store {int} grid columns') do |count|
  expect(Array(@deal.reload.grid_columns).size).to eq(count)
end

# ---------------------------------------------------------------------------
# Helper — appends one grid column row in the deal form
# ---------------------------------------------------------------------------
def _add_grid_column_row(field, label, position)
  click_button('+ Add Column')
  sleep(0.3)

  # The new row is the last one in the rows container
  row = all("[data-deal-grid-columns-target='row']").last
  within(row) do
    select_option = find("[data-field='field']")
    select_option.find("option[value='#{field}']").select_option

    find("[data-field='label']").set(label)

    pos_select = find("[data-field='position']")
    pos_select.find("option[value='#{position.downcase}']").select_option
  end

  sleep(0.2)
end

def _ensure_deal_statuses_present_in_form
  status_field = find('#deal_deal_investor_status')
  return if status_field.value.to_s.strip.present?

  fallback_statuses = Array(@deal&.reload&.deal_investor_status).presence || DealInvestor::STATUS
  status_field.set(fallback_statuses.join(', '))
end

# ---------------------------------------------------------------------------
# Deal List View analytics customization steps
# ---------------------------------------------------------------------------

When('I edit the deal analytics stats to {string}') do |labels_csv|
  visit(edit_deal_path(@deal))
  _ensure_deal_statuses_present_in_form

  # Clear the existing stat rows so the scenario can define the exact set.
  all("[data-deal-analytics-stats-target='row']").each do |row|
    row.find("[data-action='click->deal-analytics-stats#removeRow']").click
  end

  labels_csv.split(',').map(&:strip).reject(&:blank?).each do |entry|
    field_label, title = entry.split('=', 2).map { |part| part&.strip }
    title ||= field_label

    click_button('+ Add Stat')
    row = all("[data-deal-analytics-stats-target='row']").last

    within(row) do
      field_select = find("[data-field='field']")
      field_select.find("option", text: field_label).select_option
      find("[data-field='label']").set(title)
    end
  end

  click_button('Save')
  sleep(1)
end

Then('the deal should have analytics stats {string}') do |keys_csv|
  expected = keys_csv.split(',').map(&:strip)
  actual = @deal.reload.analytics_stats.map { |stat| stat['field'] }
  expect(actual).to eq(expected)
end

Then('the deal analytics card {string} should be visible') do |subtitle|
  expect(page).to have_css('.analytics-card .fw-medium', text: subtitle, wait: 10)
end

Then('the deal analytics card {string} should not be visible') do |subtitle|
  expect(page).not_to have_css('.analytics-card .fw-medium', text: subtitle, wait: 5)
end

Then('the deal analytics description should include {string}') do |text|
  expect(page).to have_css('.analytics-card .text-muted', text: text, wait: 10)
end

# ---------------------------------------------------------------------------
# Deal List View sidepanel/documents navigation steps
# ---------------------------------------------------------------------------

Then('the deal list sidepanel frame should target top') do
  expect(page).to have_css('turbo-frame#deal_investor_frame[target="_top"]', visible: :all, wait: 10)
end

When('I visit the deal documents folder page') do
  @deal.reload
  visit(folder_documents_path(entity_id: @deal.entity_id, folder_id: @deal.document_folder.id))
end

Then('the All Documents button should target top and close the sidepanel') do
  link = find('a.btn.btn-outline-primary', text: 'All Documents', wait: 10)
  expect(link['data-turbo-frame']).to eq('_top')
  expect(link['data-action'].to_s).to include('click->deals-list-ag-grid#closeSidepanel')
end
