Given(/^there is a user "([^"]*)"$/) do |arg1|
  @user = FactoryBot.build(:user, entity: @entity)
  key_values(@user, arg1)
  @user.save!
  puts "\n####User####\n"
  puts @user.to_json
  puts "User Permissions: #{@user.permissions}"
end

Given('there is a user {string} for an entity {string}') do |arg1, arg2|
  @entity = FactoryBot.build(:entity, :with_exchange_rates)
  key_values(@entity, arg2)
  @entity.save!
  puts "\n####Entity####\n"
  puts @entity.to_json
  puts "Entity Permissions: #{@entity.permissions}"

  # Funds need exchange rates for their calculations
  if @entity.is_fund?
    ExchangeRate.create!([
        {from: "USD", to: "INR", rate: 81.72, entity: @entity, as_of: Date.today - 10.year},
        {from: "INR", to: "USD", rate: 0.012, entity: @entity, as_of: Date.today - 10.year}
    ])
  end

  puts @entity.exchange_rates.to_json

  @user = FactoryBot.build(:user, entity: @entity)
  key_values(@user, arg1)
  @user.save!
  puts "\n####User####\n"
  puts @user.to_json
  puts "User Permissions: #{@user.permissions}"

  @entity.reload
end



Given('there is another user {string} for another entity {string}') do |arg1, arg2|
  @another_entity = FactoryBot.build(:entity)
  key_values(@another_entity, arg2)
  @another_entity.save!
  puts "\n####Another Entity####\n"
  puts @another_entity.to_json
  puts "Another Entity Permissions: #{@another_entity.permissions}"

  @another_user = FactoryBot.build(:user, entity: @another_entity)
  key_values(@another_user, arg1)
  @another_user.save!
  puts "\n####Another User####\n"
  puts @another_user.to_json
  puts "Another User Permissions: #{@another_user.permissions}"

  @another_entity.reload
end

Given('the other entity is an investor with category {string}') do |category|
  FactoryBot.create(:investor, entity: @entity, investor_entity: @another_entity, investor_name: @another_entity.name, category:)
end

Then(/^the email has the profile in the body$/) do
  current_email.body.should include("Profile")
  current_email.body.should include("Known As")
  current_email.body.should include("Role")
end

Given(/^there is an unsaved user "([^"]*)"$/) do |arg1|
  @user = FactoryBot.build(:user)
  key_values(@user, arg1)
  puts "\n####Unsaved User####\n"
  puts @user.to_json
end

Given('there is an unsaved user {string} for an entity {string}') do |arg1, arg2|
  @entity = FactoryBot.create(:entity)
  key_values(@entity, arg2)

  @user = FactoryBot.build(:user, entity: @entity)
  key_values(@user, arg1)
  puts "\n####User####\n"
  puts @user.to_json
end

Then(/^I should see the "([^"]*)"$/) do |arg1|
  expect(page).to have_content(arg1)
end

Given(/^Im a logged in user "([^"]*)"$/) do |arg1|
  steps %(
    Given there is a user "#{arg1}"
    And I am at the login page
    When I fill and submit the login page
  )
end

Given(/^Im logged in$/) do
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

Given(/^the user is logged in$/) do
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

Given('the user has role {string}') do |roles|
  roles.split(",").each do |role|
    @user.add_role role.strip.to_sym
  end
end

Given('the user has curr role {string}') do |role|
  @user.curr_role = role
  @user.save
end

Then(/^he must see the message "([^"]*)"$/) do |arg1|
  expect(page).to have_content(arg1)
end

Then(/^I must see the message "([^"]*)"$/) do |arg1|
  expect(page).to have_content(arg1)
end

When(/^I click "([^"]*)"$/) do |arg1|
  click_on(arg1)
end

Then(/^the user receives an email with "([^"]*)" as the subject$/) do |subject|
  open_email(@user.email)
  expect(current_email.subject).to eq subject
end

Then(/^the user receives an email with "([^"]*)" in the subject$/) do |subject|
  open_email(@user.email)
  expect(current_email.subject).to include subject
end
Then('the email body should contain {string}') do |body_content|
  expect(current_email.body).to include(body_content)
end

Then('the investor receives an email with {string} in the subject') do |subject|
  user = InvestorAccess.includes(:user).first.user
  open_email(user.email)
  expect(current_email.subject).to include subject
end

Then(/^the user receives no email$/) do
  open_email(@user.email)
  expect(current_email).to eq nil
end

Then(/^I should see the all the home page menus "([^"]*)"$/) do |arg1|
  arg1.split(";").each do |menu|
    click_on(menu)
    sleep(0.5)
    page.find(".back-button").click
  end
end

Then(/^I should not see the home page menus "([^"]*)"$/) do |arg1|
  arg1.split(";").each do |menu|
    puts "checking menu #{menu}"
    expect(page).to_not have_content(menu)
  end
end

When(/^I click "([^"]*)" in the side panel$/) do |arg1|
  page.find(".bar-button-menutoggle").click
  sleep(1)
  click_on(arg1)
  sleep(1)
end

When('I click the tab {string}') do |args|
  # Change this to the last .nav
  tab = all(".nav-tabs").last || all(".nav-pills").last
  within(tab) do
    click_on(args)
  end
end

Then('when I click the {string} button') do |arg1|
  click_on(arg1)
end

Then('sleep {string}') do |arg|
  sleep(arg.to_i)
end

Given('the email queue is cleared') do
  puts "######### clearing all emails #########"
  clear_emails
end

Given('I trigger the bulk action for {string}') do |bulk_action|
  click_on("Bulk Actions")
  click_on(bulk_action)
  sleep(2)
  click_on("Proceed")
  sleep(5)
end

Given('I filter the {string} by {string}') do |controller, args|
  key, value = args.split("=")
  url="#{controller}?q[c][0][a][0][name]=#{key}&q[c][0][p]=eq&q[c][0][v][0][value]=#{value}"
  visit(url)
end