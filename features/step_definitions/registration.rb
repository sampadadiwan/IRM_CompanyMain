Given(/^I am at the registration page$/) do
  visit("/")
  click_on("Sign up")
end

When(/^I fill and submit the registration page$/) do
  fields = %w[first_name last_name email phone]
  fields.each do |k|
    fill_in("user_#{k}", with: @user[k])
  end

  fill_in("user_password", with: "password")
  fill_in("user_password_confirmation", with: "password")

  find("#register_btn").click
end

Then(/^when I click the confirmation link$/) do
  User.last.email.should == @user.email
  current_email.click_link "Access Your Account"
end

Then(/^the user should be confirmed$/) do
  @saved_user = User.find_by_email(@user.email)
  @saved_user.confirmed_at.should_not be_nil

  fields = %w[first_name last_name email phone]
  fields.each do |k|
    expect(@user[k]).to eql(@saved_user[k])
  end
end



Then('the user should have the roles {string}') do |roles|
  
  puts "\n####User roles####\n"
  puts @user.roles.collect(&:name)
  roles.split(",").each do |role|
    @user.has_cached_role?(role.to_sym).should == true
  end
end
