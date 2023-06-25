Given('Im logged in as a user {string} for an entity {string}') do |arg1, arg2|
  steps %(
    Given there is a user "#{arg1}" for an entity "#{arg2}"
    And I am at the login page
    When I fill and submit the login page
  )
end

Given(/^I am at the login page$/) do
  visit("/users/sign_in")
  expect(page).to have_content("Welcome To Cap Hive")
end

When(/^I fill and submit the login page$/) do
  fill_in('user_email', with: @user.email)
  fill_in('user_password', with: "password")
  click_on("Log In")
  sleep(1)
  expect(page).to have_content("Signed in successfully")
  User.find_by_email(@user.email).sign_in_count.should == 1
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
  
  fill_in('user_email', with: @user.email)
  click_on("Log In Without Password")
  sleep(1)
end


Then('when I click on the link in the email {string}') do |link|
  current_email.click_link link
end