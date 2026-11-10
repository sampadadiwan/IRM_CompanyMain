# Steps for the "require two-factor for support and super" change (OWASP 2026-11 M8):
#   features/login/two_factor_required_roles.feature   (RR — business-rules §1)
#   features/login/two_factor_required_rollout.feature (RO — §2)
#   features/login/two_factor_turn_off.feature         (TO — §3)
#   features/security/two_factor_required_roles.feature (SEC — every refusal / direct request)
#
# The people are the cast in openspec/changes/require-2fa-privileged-roles/business-rules.md
# "Shared setup" (Ravi, Anita, Sam … Tara). Each is created on first mention, with the roles and
# two-factor state the table gives them, so a scenario names only the people it needs.
#
# Shared steps reused from elsewhere: two_factor_steps.rb (mode selection, TOTP codes),
# two_factor_sms_steps.rb (texted codes), security_auth_a_steps.rb (token API),
# security_auth_b_steps.rb (password reset), mobile_api_steps.rb (LP app sign-in).

World(ActiveSupport::Testing::TimeHelpers)

module TwoFactorRequiredWorld
  # Firm → entity type, as in the shared setup table
  TFA_FIRMS = {
    "CapHive" => "Company",
    "Sahyadri Capital" => "Investment Fund",
    "Priya Family Office" => "Investor",
    "Western Ghats Ventures" => "Investment Fund"
  }.freeze

  # name → firm, extra roles, two-factor state, phone. :super is written straight into
  # users_roles because User#forbid_bad_role refuses add_role(:super) by design.
  TFA_CAST = {
    "Ravi" => { firm: "CapHive", roles: %i[support], tfa: :off, phone: :none },
    "Anita" => { firm: "CapHive", roles: %i[support], tfa: :authenticator },
    "Sam" => { firm: "CapHive", roles: %i[super], tfa: :off },
    "Vikram" => { firm: "CapHive", roles: %i[support investor], tfa: :off },
    "Isha" => { firm: "CapHive", roles: [], tfa: :off, phone: %w[1 4155550142] },
    "Leela" => { firm: "CapHive", roles: %i[company_admin], tfa: :authenticator },
    "Meera" => { firm: "Sahyadri Capital", roles: %i[company_admin], tfa: :off },
    "Neha" => { firm: "Sahyadri Capital", roles: %i[company_admin], tfa: :authenticator },
    "Omkar" => { firm: "Sahyadri Capital", roles: %i[company_admin], tfa: :no_method },
    "Arjun" => { firm: "Sahyadri Capital", roles: [], tfa: :off },
    "Dev" => { firm: "Sahyadri Capital", roles: [], tfa: :authenticator },
    "Lena" => { firm: "Sahyadri Capital", roles: [], tfa: :no_method },
    "Tom" => { firm: "Sahyadri Capital", roles: [], tfa: :sms, phone: %w[1 4155550142] },
    "Priya" => { firm: "Priya Family Office", roles: [], tfa: :whatsapp },
    "Rahul" => { firm: "Priya Family Office", roles: %i[company_admin], tfa: :authenticator },
    "Sunita" => { firm: "Priya Family Office", roles: %i[company_admin], tfa: :authenticator },
    "Tara" => { firm: "Western Ghats Ventures", roles: %i[company_admin], tfa: :authenticator }
  }.freeze

  def tfa_firm(name)
    @tfa_firms ||= {}
    @tfa_firms[name] ||= Entity.find_by(name:) ||
                         FactoryBot.create(:entity, name:, entity_type: TFA_FIRMS.fetch(name), enable_funds: true)
  end

  def tfa_email(name)
    "#{name.downcase}@#{TFA_CAST.fetch(name)[:firm].parameterize}.test"
  end

  # The cast member, created on first use
  def tfa_user(name)
    @tfa_users ||= {}
    @tfa_users[name] ||= User.find_by(email: tfa_email(name)) || tfa_create_user(name)
  end

  def tfa_create_user(name)
    spec = TFA_CAST.fetch(name)
    user = FactoryBot.create(:user, entity: tfa_firm(spec[:firm]), first_name: name, last_name: "Tester",
                                    email: tfa_email(name), enable_support: true)
    # Phone first (raw columns: the fixture may hold a number the dialable check would refuse)
    case spec[:phone]
    when :none then user.update_columns(phone: nil, call_code: nil)
    when Array then user.update_columns(call_code: spec[:phone][0], phone: spec[:phone][1])
    end
    spec[:roles].each { |role| tfa_grant_role(user, role) }
    tfa_set_two_factor(user.reload, spec[:tfa])
    user.reload
  end

  def tfa_grant_role(user, role)
    if role.to_sym == :super
      # User#forbid_bad_role refuses add_role(:super) on purpose; production grants it in the DB
      role_row = Role.find_or_create_by!(name: "super")
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(["INSERT INTO users_roles (user_id, role_id) VALUES (?, ?)", user.id, role_row.id])
      )
    else
      user.add_role(role)
    end
    user.reload
  end

  def tfa_set_two_factor(user, state)
    case state
    when :authenticator
      user.update!(two_factor_enabled: true, otp_secret: User.generate_otp_secret, two_factor_mode: "authenticator")
    when :no_method
      user.update!(two_factor_enabled: true, two_factor_mode: nil)
    when :whatsapp
      user.update!(two_factor_enabled: true, otp_secret: User.generate_otp_secret, two_factor_mode: "whatsapp",
                   whatsapp_enabled: true)
    when :sms
      user.update!(two_factor_enabled: true, otp_secret: User.generate_otp_secret, two_factor_mode: "sms")
    end
  end

  # Mail delivered to `name` whose subject includes `subject` (jobs run inline under Cucumber)
  def tfa_mails_to(name, subject = nil)
    email = tfa_user(name).email
    ActionMailer::Base.deliveries.select do |mail|
      mail.to.to_a.include?(email) && (subject.nil? || mail.subject.to_s.include?(subject))
    end
  end

  # A bare Rails integration session (no browser): for direct requests and "a session that started
  # earlier". Signs in with the password, then — when the user has a verified method — with the
  # current authenticator code, exactly as the website would.
  def tfa_session(name)
    @tfa_sessions ||= {}
    @tfa_sessions[name] ||= begin
      user = tfa_user(name)
      session = ActionDispatch::Integration::Session.new(Rails.application)
      if user.two_factor_required? && !user.two_factor_verified?
        # A required user with no method can't finish a sign-in any more (set-up comes first), so their
        # session is one from before the deploy: made by Warden on the next request, without the form
        login_as(user, scope: :user)
        session.get "/users/#{user.id}"
      else
        session.post "/users/sign_in", params: { user: { email: user.email, password: "password" } }
        session.post "/two_factor", params: { otp_code: user.reload.current_otp } if session.response.location.to_s.include?("/two_factor/new")
      end
      session
    end
  end
end
World(TwoFactorRequiredWorld)

# ── Clock and region stage ────────────────────────────────────────────────────

# E4 — watch the error log before the bad value is first read
Given("the error log is watched") do
  allow(Rails.logger).to receive(:error).and_call_original
end

# Times are in the app time zone (New Delhi), e.g. "2026-12-02 10:00"
Given("it is {string} in India") do |time|
  travel_back
  travel_to Time.zone.parse(time)
  # The session cookie's expiry is stamped from the travelled clock; keep it a browser-session
  # cookie so a later travel does not drop it (features/support/evergreen_session_cookie.rb)
  EvergreenSessionCookie.travelling = true
end

After do
  # Undo any clock travel so nothing leaks to the next scenario in this worker
  travel_back
end

# ── People ────────────────────────────────────────────────────────────────────

Given("the people {string} exist") do |names|
  names.split(",").map(&:strip).each { |name| tfa_user(name) }
end

Given("{string} is granted the {string} role") do |name, role|
  tfa_grant_role(tfa_user(name), role)
end

Given("{string} loses the {string} role") do |name, role|
  tfa_user(name).remove_role(role.to_sym)
end

# E12 — what SupportClientMapping#switch leaves behind: the client's firm and its company_admin role
Given("{string} is switched into {string}") do |name, firm|
  user = tfa_user(name)
  user.update_columns(entity_id: tfa_firm(firm).id)
  tfa_grant_role(user, :company_admin)
end

# E14 — WhatsApp mode, but the number has since been removed
Given("{string} is in WhatsApp mode with no phone number") do |name|
  user = tfa_user(name)
  user.update_columns(two_factor_mode: "whatsapp", whatsapp_enabled: true, phone: nil, call_code: nil)
end

Given("{string} has set up the authenticator app") do |name|
  tfa_set_two_factor(tfa_user(name), :authenticator)
end

# Makes the cast member the subject of the shared @user-based steps (TOTP, password reset …)
Given("I am {string}") do |name|
  @user = tfa_user(name)
end

# ── Sign-in ───────────────────────────────────────────────────────────────────

When("{string} signs in with their password") do |name|
  @user = tfa_user(name)
  # Always a fresh browser: a sign-in page visited while someone is signed in just redirects away
  Capybara.reset_sessions!
  visit "/users/sign_in"
  fill_in("user_email", with: @user.email)
  fill_in("user_password", with: "password")
  click_on("Log In")
end

When("{string} opens a sign-in link back to their user page") do |name|
  @user = tfa_user(name)
  signed_id = @user.signed_id(purpose: User::MAGIC_LINK_PURPOSE, expires_in: 10.minutes)
  visit "/users/no_password_login?signed_id=#{signed_id}&redirect_to=#{CGI.escape(user_path(@user))}"
end

When("I enter {int} wrong set-up codes") do |count|
  count.times do
    fill_in("otp_code", with: "000000")
    click_on("Confirm & Enable 2FA")
  end
end

Then("I see the required set-up screen for the role {string}") do |label|
  expect(page).to have_current_path(select_mode_two_factor_path, wait: 10)
  expect(page).to have_content("Set Up Two-Factor Authentication")
  expect(page).to have_css("#two_factor_required_banner",
                           text: "Two-factor authentication is required for your role (#{label}). " \
                                 "Choose a method to finish signing in.")
end

Then("I see the set-up screen without the required banner") do
  expect(page).to have_current_path(select_mode_two_factor_path, wait: 10)
  expect(page).to have_no_css("#two_factor_required_banner")
end

Then("only the authenticator app is offered, preselected") do
  expect(page).to have_checked_field("two_factor_mode", with: "authenticator")
  expect(page).to have_no_field("two_factor_mode", with: "whatsapp")
  expect(page).to have_no_field("two_factor_mode", with: "sms")
end

Then("I am signed in with the password only") do
  expect(page).to have_content("Signed in successfully")
  expect(page).to have_no_current_path(%r{\A/two_factor}, wait: 5)
  expect(page).to have_no_current_path(new_user_session_path)
end

Then("I am on my user page") do
  expect(page).to have_current_path(user_path(@user), wait: 10)
end

# ── State and email ───────────────────────────────────────────────────────────

Then("{string} has two-factor on with the {string} method") do |name, mode|
  user = tfa_user(name).reload
  expect(user.two_factor_enabled).to be(true)
  expect(user.two_factor_mode).to eq(mode)
end

Then("{string} has two-factor off with no method") do |name|
  user = tfa_user(name).reload
  expect(user.two_factor_enabled).to be(false)
  expect(user.two_factor_mode).to be_blank
end

Then("{string} has two-factor on with no method") do |name|
  user = tfa_user(name).reload
  expect(user.two_factor_enabled).to be(true)
  expect(user.two_factor_mode).to be_blank
end

Then("{string} is emailed {string} dated {string}") do |name, subject, date|
  mail = tfa_mails_to(name, subject).last
  expect(mail).to be_present, "no \"#{subject}\" email to #{name}: #{ActionMailer::Base.deliveries.map(&:subject)}"
  expect(mail.body.encoded).to include(date)
end

Then("{string} is emailed {string}") do |name, subject|
  expect(tfa_mails_to(name, subject)).to be_present,
                                         "no \"#{subject}\" email to #{name}: #{ActionMailer::Base.deliveries.map(&:subject)}"
end

Then("{string} is not emailed {string}") do |name, subject|
  expect(tfa_mails_to(name, subject)).to be_empty
end

Then("the error log says {string}") do |text|
  expect(Rails.logger).to have_received(:error).with(a_string_including(text))
end

Then("a WhatsApp code was sent") do
  expect(SendOtpToWhatsappJob).to have_received(:perform_later)
end

# ── Other doors: token API, LP app ────────────────────────────────────────────

# E19 — a Profile › API tokens token made from the website before the date
Given("{string} has an API token {string}") do |name, token_name|
  @tfa_api_tokens ||= {}
  # mint! returns the row and the raw access-token string (shown once on the website)
  _api_token, access_token = ApiToken.mint!(user: tfa_user(name), name: token_name)
  @tfa_api_tokens[token_name] = access_token
end

When("the API token {string} reads {string}") do |token_name, path|
  @tfa_api = ActionDispatch::Integration::Session.new(Rails.application)
  @tfa_api.get path, headers: { "Authorization" => "Bearer #{@tfa_api_tokens.fetch(token_name)}",
                                "Accept" => "application/json" }
end

Then("the API answers {int}") do |status|
  expect(@tfa_api.response.status).to eq(status), @tfa_api.response.body.to_s.truncate(300)
end

Then("no token row was made for {string}") do |name|
  expect(Devise::Api::Token.where(resource_owner: tfa_user(name)).count).to eq(0)
end

Then("{string} has {int} failed password attempt(s) recorded") do |name, count|
  expect(tfa_user(name).reload.failed_attempts).to eq(count)
end

# X5 / E18 — Vikram: CapHive support who is also an LP in the mobile app
Given("{string} is a CapHive support user who is also an LP") do |email|
  steps %(Given a mobile investor "#{email}" of "Vikram Family" with fund manager "Sahyadri Capital")
  User.find_by!(email:).add_role(:support)
end

Then("{string} has no live phone") do |email|
  expect(MobileDevice.where(user: User.find_by!(email:)).count).to eq(0)
end

# ── Phase 2: banner, Set up now, Login as, roll-out ──────────────────────────

# An enabled support mapping to the firm whose login-as list admits the support user (blank list
# = any support user on the mapping)
Given("{string} may Login as users of {string}") do |name, firm|
  entity = tfa_firm(firm)
  # The firm lets CapHive support in (the admin console's scope reads this permission)
  entity.permissions.set(:enable_support)
  entity.save!
  FactoryBot.create(:support_client_mapping, user: tfa_user(name), entity:, enabled: true,
                                             enable_user_login: true, end_date: Date.new(2027, 12, 31))
end

# A signed-in browser for someone with no method (password only) — before the date, or a company admin
Given("{string} is signed in on the website") do |name|
  step %("#{name}" signs in with their password)
  expect(page).to have_no_current_path(new_user_session_path, wait: 10)
end

# A signed-in browser for someone with a verified authenticator method (password, then the code)
Given("{string} is signed in on the website with their code") do |name|
  step %("#{name}" signs in with their password)
  step %(I enter a valid TOTP code)
  expect(page).to have_content("Signed in successfully")
end

When("I open the dashboard") do
  visit root_path
end

# H4 / H5 — a browser still signed in from before the deploy, when the rule did not exist: the session was
# made without the set-up step, as a session from that day was (Warden, no sign-in form)
Given("{string} still has a website session from before the deploy") do |name|
  @user = tfa_user(name)
  Capybara.reset_sessions!
  login_as(@user, scope: :user)
end

When("I press {string} on my user page") do |label|
  click_on(label)
end

# The admin console's "Click To Login" posts this same request; rack_test submits it directly
When("I use Login as on {string}") do |name|
  page.driver.submit :post, login_as_user_path(tfa_user(name)), {}
end

Then("I am acting as {string}") do |name|
  expect(page).to have_content("Signed in as #{tfa_user(name).full_name}")
end

Then("I am still signed in as {string} and not acting as anyone") do |name|
  expect(page).to have_no_content("Signed in as ")
  # The profile menu belongs to the support user, not the client
  visit user_path(tfa_user(name))
  expect(page).to have_content(tfa_user(name).email)
end

# ── Rake tasks ────────────────────────────────────────────────────────────────

# Runs a two_factor_required:* task in-process and keeps what it printed
def tfa_run_rake(task, execute:)
  Rails.application.load_tasks unless Rake::Task.task_defined?("two_factor_required:report")
  saved_execute = ENV.fetch("EXECUTE", nil)
  execute ? ENV["EXECUTE"] = "1" : ENV.delete("EXECUTE")
  output = StringIO.new
  saved_stdout = $stdout
  $stdout = output
  begin
    Rake::Task[task].reenable
    Rake::Task[task].invoke
  ensure
    $stdout = saved_stdout
    saved_execute.nil? ? ENV.delete("EXECUTE") : ENV["EXECUTE"] = saved_execute
  end
  @tfa_rake_output = output.string
end

When("ops runs {string}") do |task|
  tfa_run_rake(task, execute: false)
end

When("ops runs {string} with EXECUTE=1") do |task|
  tfa_run_rake(task, execute: true)
end

Then("the task prints {string}") do |text|
  expect(@tfa_rake_output).to include(text), @tfa_rake_output
end

# H7 — counts only: no cast member's name or email is printed
Then("the task prints no names or emails") do
  (@tfa_users || {}).each do |name, user|
    expect(@tfa_rake_output).not_to include(user.email)
    expect(@tfa_rake_output).not_to include(name)
  end
end

# ── Remember-me cookie and website tokens (end_unverified_access) ────────────

# The same signed cookie Devise's rememberable writes when "Remember me" is ticked at sign-in
Given("{string} has a remember-me cookie") do |name|
  user = tfa_user(name)
  user.remember_me!
  # Devise accepts the cookie only when it was generated AFTER remember_created_at; the clock is
  # frozen by travel_to, so stamp it one second later, as a real sign-in a moment later would
  generated_at = 1.second.from_now.utc.to_f.to_s
  jar = ActionDispatch::TestRequest.create.cookie_jar
  jar.signed["remember_user_token"] = { value: [user.to_key, user.rememberable_value, generated_at],
                                        expires: 2.weeks.from_now }
  @tfa_remember_cookies ||= {}
  @tfa_remember_cookies[name] = jar["remember_user_token"]
end

# A browser whose 60-minute session cookie has expired, holding only the remember-me cookie
When("{string} comes back with only the remember-me cookie") do |name|
  @tfa_return = ActionDispatch::Integration::Session.new(Rails.application)
  @tfa_return.cookies["remember_user_token"] = @tfa_remember_cookies.fetch(name)
  @tfa_return.get "/users/#{tfa_user(name).id}"
end

Then("they are signed in from the cookie") do
  expect(@tfa_return.response.status).to eq(200), "got #{@tfa_return.response.status} → #{@tfa_return.response.location}"
end

Then("they are sent to sign in") do
  expect(@tfa_return.response).to be_redirect
  expect(@tfa_return.response.location).to include("/users/sign_in")
end

# ── Direct requests (SEC) ─────────────────────────────────────────────────────

# A signed-in integration session that started at an earlier time (password only for a user with
# no method, password + code for a user with one)
Given("{string} has a website session") do |name|
  tfa_session(name)
end

When("{string} posts to start two-factor set-up for {string}") do |actor, target|
  session = tfa_session(actor)
  session.post "/users/#{tfa_user(target).id}/start_two_factor_setup"
  @tfa_last_session = session
end

When("{string} posts Login as for {string}") do |actor, target|
  session = tfa_session(actor)
  session.post "/users/#{tfa_user(target).id}/login_as"
  @tfa_last_session = session
end

Then("the direct request is refused with {string}") do |message|
  response = @tfa_last_session.response
  if response.redirect?
    expect(@tfa_last_session.flash[:alert].to_s).to include(message)
  else
    expect(response.status).to be >= 400
    expect(response.body).to include(message)
  end
end

Then("the session of {string} is not acting as anyone") do |name|
  expect(tfa_session(name).session[:support_user_id]).to be_nil
end

Then("{string} is still signed in") do |name|
  session = tfa_session(name)
  session.get "/users/#{tfa_user(name).id}"
  expect(session.response.status).to eq(200)
end

Then("the two-factor flag of {string} is {word}") do |name, value|
  expect(tfa_user(name).reload.two_factor_enabled).to be(value == "on")
end

# ── Help text and tooltips (every user-facing change explains itself) ────────

Then("the alert offers to set up two-factor") do
  expect(page).to have_css("#alert #two_factor_setup_alert_button")
end

# ── Phase 3: turning two-factor off ──────────────────────────────────────────

# A fresh, real cache for the step-up counters and the send-code cooldown (the test env's
# :null_store keeps nothing); restored after the scenario
Before("@two_factor_cache") do
  @tfa_saved_cache = Rails.cache
  Rails.cache = ActiveSupport::Cache::MemoryStore.new
end

After("@two_factor_cache") do
  Rails.cache = @tfa_saved_cache if @tfa_saved_cache
end

# The code a user would type right now. A code already used to sign in cannot be used again in
# the same 30-second step (anti-replay), so scenarios let a minute pass first.
def tfa_current_code(name)
  user = tfa_user(name).reload
  user.sms_mode? ? @twilio.last_code : user.current_otp
end

When("I open my user page") do
  visit user_path(@user)
  expect(page).to have_content("Two-Factor Authentication", wait: 10)
end

When("I open the user page of {string}") do |name|
  visit user_path(tfa_user(name))
  expect(page).to have_content("Two-Factor Authentication", wait: 10)
end

When("I open my Edit profile") do
  visit edit_user_path(@user)
end

# The popup's form, submitted as the browser would once the button is enabled (rack_test cannot
# run the Stimulus controller that enables it; the Playwright scenarios press it for real)
When("I submit the turn-off popup with password {string} and the current code") do |password|
  page.driver.submit :post, disable_two_factor_user_path(@user),
                     { password:, otp_code: tfa_current_code(@user.first_name), acknowledge: "1" }
end

When("I submit the turn-off popup with password {string} and the code {string}") do |password, code|
  page.driver.submit :post, disable_two_factor_user_path(@user), { password:, otp_code: code, acknowledge: "1" }
end

When("I submit the turn-off popup with password {string} and no code") do |password|
  page.driver.submit :post, disable_two_factor_user_path(@user), { password:, acknowledge: "1" }
end

When("I press Send code on my user page") do
  page.driver.submit :post, send_two_factor_code_user_path(@user), {}
end

Then("the turn-off popup has no code field") do
  within("#disableTwoFactorModal") do
    expect(page).to have_field("disable_two_factor_password", visible: :all)
    expect(page).to have_no_field("disable_two_factor_code", visible: :all)
  end
end

Then("the turn-off popup explains why the password and code are asked") do
  expect(page).to have_css("#disableTwoFactorModal #disable_two_factor_why",
                           text: "so that someone using your open session can't remove your second factor", visible: :all)
end

# Playwright: the real popup, buttons and Stimulus controller
When("I turn off two-factor in the popup with password {string}") do |password|
  find("#disable_two_factor_button").click
  expect(page).to have_css("#disableTwoFactorModal.show #disable_two_factor_effects", wait: 10)
  within("#disableTwoFactorModal") do
    fill_in("disable_two_factor_password", with: password)
    expect(page).to have_button("Turn off 2FA", disabled: true)
    if page.has_button?("disable_two_factor_send_code", wait: 0)
      click_on("disable_two_factor_send_code")
      expect(page).to have_css("#disable_two_factor_send_status",
                               text: "A new code is on its way. It can take a few seconds to arrive.", wait: 10)
    end
    fill_in("disable_two_factor_code", with: tfa_current_code(@user.first_name)) if page.has_field?("disable_two_factor_code", wait: 0)
    check("disable_two_factor_acknowledge")
    expect(page).to have_button("Turn off 2FA", disabled: false, wait: 5)
    click_on("Turn off 2FA")
  end
end

Then("I see the {string} badge with a tooltip naming {string}") do |label, role|
  badge = find("#two_factor_required_badge", text: label)
  expect(badge[:title]).to include("#{role} accounts must use two-factor authentication.")
end

Then("I see no {string} button") do |label|
  expect(page).to have_no_button(label)
end

Then("I see the {string} button") do |label|
  expect(page).to have_button(label)
end

# D12 / E38 — the refusal explains itself where the admin looks
Then("the Turn off 2FA control is disabled with the hint {string}") do |hint|
  wrapper = find("#disable_two_factor_admin_hint")
  expect(wrapper[:title]).to eq(hint)
  expect(wrapper).to have_button("Turn off 2FA", disabled: true)
end

Then("the audit log records the turn-off of {string}") do |name|
  audit = tfa_user(name).audits.reorder(:id).last
  expect(audit.audited_changes).to include("two_factor_enabled" => [true, false])
  expect(audit.comment).to include("Two-factor turned off by self")
end

Then("{string} has {int} wrong turn-off codes counted") do |name, count|
  expect(Rails.cache.read(TwoFactorDisable.code_attempts_key(tfa_user(name))).to_i).to eq(count)
end

Given("{string} has {int} wrong turn-off codes in the last 10 minutes") do |name, count|
  Rails.cache.write(TwoFactorDisable.code_attempts_key(tfa_user(name)), count, expires_in: 10.minutes)
end

Given("{string} already has {int} wrong passwords counted") do |name, count|
  tfa_user(name).update_columns(failed_attempts: count)
end

Given("{string} is no longer active") do |name|
  tfa_user(name).update_columns(active: false)
end

Then("{string} is locked") do |name|
  expect(tfa_user(name).reload.access_locked?).to be(true)
end

# E41 — the mailer renders under whatever locale the triggering thread had
When("{string} turns two-factor off while the app runs in Japanese") do |name|
  user = tfa_user(name)
  I18n.with_locale(:ja) do
    @tfa_result = TwoFactorDisable.call(user:, actor: user, password: "password", code: user.current_otp)
  end
  expect(@tfa_result).to be_success, @tfa_result[:errors].to_s
end

Then("WhatsApp codes were sent {int} time(s)") do |count|
  expect(SendOtpToWhatsappJob).to have_received(:perform_later).exactly(count).times
end

# E33 — the origin region switched two-factor off for its own user; this region applies it
Given("{string} lives in IN and US") do |name|
  tfa_user(name).update_columns(primary_region: "IN", regions: "IN,US")
end

When("the origin region syncs {string} with two-factor switched off") do |name|
  user = tfa_user(name).reload
  user_json = user.as_json.merge("two_factor_enabled" => false, "two_factor_mode" => nil)
  @payload = { action: "UPSERT", event_id: SecureRandom.uuid, as_of: Time.now.utc.iso8601(3),
               origin_region: "IN", target_region: ENV.fetch("REGION", nil), ccf_hex: SecureRandom.hex(32),
               user: user_json, entity: user.entity.as_json, roles: user.roles.map { |r| { name: r.name } }.uniq }
  step %(I POST the signed request to "/internal/sync/users")
end

# ── Direct requests (SEC, phase 3) ────────────────────────────────────────────

When("{string} posts to turn off two-factor for {string} with the right password and code") do |actor, target|
  session = tfa_session(actor)
  session.post "/users/#{tfa_user(target).id}/disable_two_factor",
               params: { password: "password", otp_code: tfa_user(target).reload.current_otp }
  @tfa_last_session = session
end

When("{string} posts to turn off two-factor for {string}") do |actor, target|
  session = tfa_session(actor)
  session.post "/users/#{tfa_user(target).id}/disable_two_factor", params: { password: "password", otp_code: "123456" }
  @tfa_last_session = session
end

When("{string} posts to send a two-factor code for {string}") do |actor, target|
  session = tfa_session(actor)
  session.post "/users/#{tfa_user(target).id}/send_two_factor_code"
  @tfa_last_session = session
end

When("{string} sends a JSON update switching off two-factor for {string}") do |actor, target|
  session = tfa_session(actor)
  session.patch "/users/#{tfa_user(target).id}.json", params: { user: { two_factor_enabled: false } }, as: :json
  @tfa_last_session = session
end

When("{string} submits the edit form switching off two-factor for {string}") do |actor, target|
  session = tfa_session(actor)
  session.patch "/users/#{tfa_user(target).id}", params: { user: { two_factor_enabled: "0" } }
  @tfa_last_session = session
end

Then("the edit form is shown again with {string}") do |message|
  response = @tfa_last_session.response
  expect(response.status).to eq(422)
  expect(CGI.unescapeHTML(response.body)).to include(message)
end

Then("the JSON answer is {int} with {string}") do |status, message|
  response = @tfa_last_session.response
  expect(response.status).to eq(status), response.body.to_s.truncate(300)
  expect(response.body).to include(message)
end

# Bearer requests: an API token made on the website, used by a script
When("the API token {string} posts to {string} for {string}") do |token_name, action, name|
  @tfa_api = ActionDispatch::Integration::Session.new(Rails.application)
  @tfa_api.post "/users/#{tfa_user(name).id}/#{action}",
                params: { password: "password", otp_code: "123456" },
                headers: { "Authorization" => "Bearer #{@tfa_api_tokens.fetch(token_name)}", "Accept" => "application/json" }
end

Then("the API answers {int} with {string}") do |status, text|
  expect(@tfa_api.response.status).to eq(status), @tfa_api.response.body.to_s.truncate(300)
  expect(@tfa_api.response.body).to include(text)
end

# X19 — the admin console's edit form for a user (Administrate)
When("I untick two-factor for {string} in the admin console") do |name|
  visit edit_admin_user_path(tfa_user(name))
  uncheck("user_two_factor_enabled")
  click_on("Update User")
end

# X24 — support acting as the user, in a browser
When("I post a turn-off for {string} from this browser") do |name|
  page.driver.submit :post, disable_two_factor_user_path(tfa_user(name)), { password: "password", otp_code: "123456" }
end

# E30 — Lena switched two-factor on from Edit profile while signed in, and has not signed out since
Given("{string} signed in before switching two-factor on") do |name|
  user = tfa_user(name)
  user.update_columns(two_factor_enabled: false, two_factor_mode: nil)
  step %("#{name}" is signed in on the website)
  user.update_columns(two_factor_enabled: true)
end

# E39 — "Change 2FA Method" on the user's own page (the self-service reset, password re-proven)
When("I submit a self reset with password {string}") do |password|
  page.driver.submit :post, reset_two_factor_user_path(@user), { password:, acknowledge: "1" }
end

# X25 — someone holding the signed-in browser, guessing the password
When("{string} posts to turn off two-factor for {string} with a guessed password") do |actor, target|
  session = tfa_session(actor)
  session.post "/users/#{tfa_user(target).id}/disable_two_factor", params: { password: "guess-1234", otp_code: "123456" }
  @tfa_last_session = session
end

# Every security email says why it was sent and what to do if it was not the reader
Then("the email {string} to {string} says {string}") do |subject, name, text|
  mail = tfa_mails_to(name, subject).last
  expect(mail).to be_present
  expect(CGI.unescapeHTML(mail.body.encoded.gsub(/\s+/, " "))).to include(text)
end
