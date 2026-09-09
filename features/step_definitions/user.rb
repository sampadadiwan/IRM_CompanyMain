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

  # @investor_user / @investor_access are set by "there is an existing investor ... with ... users"
  When('I update the investor user\'s call_code to {string}, phone to {string} and email to {string}') do |call_code, phone, email|
    @investor_user.update!(call_code:, phone:, email:)
  end

  Then('the investor access for the investor user should have phone {string} and email {string}') do |phone, email|
    @investor_access.reload
    expect(@investor_access.phone).to eq(phone)
    expect(@investor_access.email).to eq(email)
  end

  # Submits the roles form for another user directly against the update endpoint (rather than
  # driving the select2 widget), since these scenarios exercise UsersController#update's role
  # handling rather than the JS widget. The default Capybara driver here is a real browser
  # (Playwright), which has no rack_test-style driver.post/submit, so we build and submit a
  # real hidden form via JS instead - the same workaround used in portco_kpi_workflow_steps.rb.
  When('I update the roles of {string} to {string}') do |email, roles|
    submit_role_update(User.find_by!(email:), roles.split(",").map(&:strip))
  end

  # Simulates a crafted request from a user who cannot see the roles field at all (it's only
  # rendered for company admins), to prove the server-side guard - not just the hidden UI -
  # blocks a non company admin from granting themselves the company_admin role.
  When('I directly submit a role update of {string} for myself') do |role|
    submit_role_update(@user, [role])
  end

  # Deselecting every option in the roles <select> still submits one user[role_name][] field
  # with an empty value - that's Rails' auto hidden field for multiple selects (see the
  # include_hidden comment in _form.html.erb) - rather than omitting the param entirely.
  When('I remove all roles from {string}') do |email|
    submit_role_update(User.find_by!(email:), [""])
  end

  def submit_role_update(target_user, roles)
    # Any already-rendered page on the app gives us a document to build the form in and the
    # right origin to submit against - the user's own show page is used elsewhere in this
    # suite (see "I should see the user details on the details page"), so it's known to render.
    visit(user_path(target_user))

    role_inputs = roles.map { |role| "add('user[role_name][]', #{role.to_json});" }.join("\n      ")

    page.execute_script(<<~JS)
      (function () {
        const f = document.createElement('form'); f.method = 'POST'; f.action = '#{user_path(target_user)}';
        const add = (n, v) => { const i = document.createElement('input'); i.type = 'hidden'; i.name = n; i.value = v; f.appendChild(i); };
        add('authenticity_token', document.querySelector('meta[name="csrf-token"]')?.content || '');
        add('_method', 'patch');
        #{role_inputs}
        document.body.appendChild(f); f.submit();
      })();
    JS
    sleep(1)
    expect(page).to have_text("User was successfully updated.")
  end

  Then('the user {string} should have the roles {string}') do |email, roles|
    target = User.find_by!(email:)
    roles.split(",").each do |role|
      expect(target.has_cached_role?(role.strip.to_sym)).to be true
    end
  end

  Then('the user {string} should not have the role {string}') do |email, role|
    target = User.find_by!(email:)
    expect(target.has_cached_role?(role.to_sym)).to be false
  end

  Then('the user should not have the role {string}') do |role|
    @user.reload
    expect(@user.has_cached_role?(role.to_sym)).to be false
  end

  # ── Phone number validation (User#phone_must_be_dialable) ──────────────────

  Given('there is an existing user with call_code {string} and phone {string}') do |call_code, phone|
    @phone_user = FactoryBot.create(:user, entity: @user.entity, call_code:, phone:)
  end

  # Bypasses validation on the way in, which is the whole point: this is the shape of the
  # rows that already exist and must stay editable.
  Given('there is an existing user whose stored phone {string} cannot be dialled') do |phone|
    @phone_user = FactoryBot.create(:user, entity: @user.entity, call_code: "91")
    @phone_user.update_columns(phone:)
    @phone_user.reload
    expect(@phone_user.sms_available?).to be(false)
  end

  When("I change that user's phone to {string}") do |phone|
    @phone_user.phone = phone
    @phone_save_result = @phone_user.save
  end

  When("I change that user's last name to {string}") do |last_name|
    @phone_user.last_name = last_name
    @phone_save_result = @phone_user.save
  end

  Then('the user should not be saved') do
    expect(@phone_save_result).to be(false)
  end

  Then('the user should be saved') do
    expect(@phone_save_result).to be(true)
  end

  Then('the phone error should mention the country code {string}') do |call_code|
    expect(@phone_user.errors[:phone].join).to include("+#{call_code}")
  end

  Then("that user's phone should still be {string}") do |phone|
    expect(@phone_user.reload.phone).to eq(phone)
  end
