Given('Im logged in as a user {string} for an entity {string}') do |arg1, arg2|
  steps %(
    Given there is a user "#{arg1}" for an entity "#{arg2}"
    And I am at the login page
    When I fill and submit the login page
  )
end

Given('Im logged in as a user {string} for an existing entity {string}') do |arg1, arg2|
  steps %(
    Given there is a user "#{arg1}" for an existing entity "#{arg2}"
    And I am at the login page
    When I fill and submit the login page
  )
end


Given('I log in with email {string}') do |email|
  @user = User.find_by_email(email)
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

Given('I log in with email {string} on the existing page') do |email|
  @user = User.find_by_email(email)
  steps %(
    When I fill and submit the login page
  )
end


Given(/^I am at the login page$/) do
  visit("/users/sign_in")
  # expect(page).to have_content("Welcome To Cap Hive")
end

Given('I am at the login page without password') do
  visit("/users/sign_in")
  # expect(page).to have_content("Welcome To Cap Hive")
end

When(/^I fill and submit the login page$/) do
  fill_in('user_email', with: @user.email)
  fill_in('user_password', with: "password")
  click_on("Log In")
  # Wait for Devise to redirect away from the sign-in page before reading the DB.
  # A fixed sleep is too short under parallel load; Capybara retries until true.
  expect(page).not_to have_current_path('/users/sign_in', wait: 15)
  User.find_by_email(@user.email).sign_in_count.should > 0
end

When(/^I fill the password incorrectly and submit the login page$/) do
  fill_in('user_email', with: @user.email)
  fill_in('user_password', with: "Wrong pass")
  click_on("Log In")
  sleep(1)
end

When('I fill and submit the login without password') do
  @user.confirmed_at = nil
  @user.save

  fill_in('user_email_wo_pass', with: @user.email)
  sleep(5)
  click_on("Log In Via Email Link")
  sleep(2)
end


Then('when I click on the link in the email {string}') do |link|
  current_email.click_link link
end

Given('I log out') do
  # visit(destroy_user_session_path)
  visit("entities/dashboard")
  sleep(2)
  find("#profile_menu").click
  click_on("Log Out")
  click_on("Logout")
end

Given('I login as the investor user') do
  @user = @investor_user
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

Given('I login as the portfolio company user') do
  @user = @portfolio_company.investor_entity.employees.first
  @user ||= FactoryBot.create(:user, entity: @portfolio_company.investor_entity)
  @user.add_role(:company_admin)
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end
