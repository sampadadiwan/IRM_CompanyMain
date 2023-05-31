  Given('I am at the users page') do
    visit(users_path)
  end

  When('I create a new user {string}') do |arg|
    @new_user = FactoryBot.build(:user)
    key_values(@new_user, arg)
    click_on("New User")
    fill_in('user_first_name', with: @new_user.first_name)
    fill_in('user_last_name', with: @new_user.last_name)
    fill_in('user_email', with: @new_user.email)
    fill_in('user_phone', with: @new_user.phone)

    fill_in('user_password', with: "password")
    fill_in('user_password_confirmation', with: "password")

    click_on("Save")
  end

  Then('an user should be created') do
    @created_user = User.last
    @created_user.first_name.should == @new_user.first_name
    @created_user.last_name.should == @new_user.last_name
    @created_user.email.should == @new_user.email
    @created_user.phone.should == @new_user.phone
    @created_user.entity_id.should == @user.entity_id
  end

  Then('I should see the user details on the details page') do
    visit(user_path(@created_user))
    expect(page).to have_content(@created_user.first_name)
    expect(page).to have_content(@created_user.last_name)
    expect(page).to have_content(@created_user.phone)
    expect(page).to have_content(@created_user.email)
    expect(page).to have_content(@created_user.entity.name)
  end

  Then('I should see the user in all users page') do
    visit(users_path)
    if(@user.entity.entity_type == "Holding")
        expect(page).to have_no_content(@created_user.first_name)
        expect(page).to have_no_content(@created_user.last_name)
    else
        expect(page).to have_content(@created_user.first_name)
        expect(page).to have_content(@created_user.last_name)
        expect(page).to have_content(@created_user.entity.name)
    end
  end


  Then('the created user should have the roles {string}') do |roles|

    puts "\n####User roles####\n"
    puts @created_user.roles.collect(&:name)
    roles.split(",").each do |role|
      @created_user.has_cached_role?(role.to_sym).should == true
    end
  end

  Given('update my password having phone {string}') do |string|
    @user.update_columns(whatsapp_enabled: true)
    @user.phone = string
    @user.call_code = "91"
    @user.password = "new_test_password"
    @user.save!
  end

  Then('a whatsapp notification is sent indicating account update') do
    sleep(8) # wait for whatsapp message to be sent
    body = WhatsappNotifier.get_messages(@user.phone_with_call_code,1,1)
    body = JSON.parse(body)
    body['messages']['items'].first['eventDescription'].include?('account_update_alert_1').should == true
  end

