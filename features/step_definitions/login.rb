Given('Im logged in as a user {string} for an entity {string}') do |arg1, arg2|
  steps %(
    Given there is a user "#{arg1}" for an entity "#{arg2}"
  )
  log_in(@user)
end

Given('Im logged in as a user {string} for an existing entity {string}') do |arg1, arg2|
  steps %(
    Given there is a user "#{arg1}" for an existing entity "#{arg2}"
  )
  log_in(@user)
end


Given('I log in with email {string}') do |email|
  @user = User.find_by_email(email)
  log_in(@user)
end

# For step definitions that need "log in as @user" as one step of a larger `steps %(...)` block.
# Feature files that test the login form itself keep the explicit
# "I am at the login page" / "I fill and submit the login page" pair.
Given('I am signed in as the current user') do
  log_in(@user)
end

# Signs `user` in for a scenario whose subject is NOT the login form - which is almost all of them.
#
# The form login costs two full page loads (the sign-in page with all its JS, then the post-submit
# redirect) on top of the landing page. Here Warden's test helper puts the user into the session of
# the next request instead, and we go straight to where the form would have landed:
# after_sign_in_path_for -> root_path (WithAuthentication). What Users::SessionsController#create
# does beyond that doesn't matter to these scenarios: its session_token cookie is never checked on
# later requests, and its "Signed in successfully" flash is only asserted in features/login/.
#
# Falls back to the real form where the form IS the thing under test:
#   - anything under features/login/ (form, magic link, 2FA flows, the sign-in flash)
#   - scenarios tagged @ui_login
#   - users with 2FA on, whose form login is a challenge rather than a sign-in
def log_in(user)
  if ui_login_required?(user)
    steps %(
      And I am at the login page
      When I fill and submit the login page
    )
    return
  end

  # Queues the sign-in onto the next request this process serves - the visit below
  Warden.test_mode!
  login_as(user, scope: :user)
  visit("/")
  # Same post-conditions as the form step: off the sign-in page, page settled, login recorded
  expect(page).not_to have_current_path('/users/sign_in', wait: 15)
  wait_for_page_to_settle
  User.find(user.id).sign_in_count.should > 0
end

def ui_login_required?(user = nil)
  # @current_scenario is set by the Before hook at the bottom of this file
  return true if @current_scenario&.location&.file.to_s.start_with?("features/login/")
  return true if @current_scenario&.source_tag_names&.include?("@ui_login")

  user&.two_factor_enabled? || false
end

World(Warden::Test::Helpers)

# Once per process, at load: Warden.test_reset! (After hook below) only exists after test_mode! has run,
# so enabling it lazily in log_in made the hook raise NoMethodError in every scenario a worker ran
# before its first login. test_mode! itself only adds a request hook that runs queued login_as
# blocks (skipping asset requests) - a no-op when nothing is queued.
Warden.test_mode!

Before do |scenario|
  @current_scenario = scenario
end

# login_as queues a hook for "the next request"; one left unconsumed (a step that failed before
# visiting) must not sign in whoever makes the next request in a later scenario.
After do
  Warden.test_reset!
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
  wait_for_page_to_settle
  User.find_by_email(@user.email).sign_in_count.should > 0
end

# Lets the post-login page finish its own requests (lazy turbo-frames, chart fetches) before the
# scenario moves on. The session is a cookie re-issued on EVERY response (expire_after in
# config/initializers/session_store.rb), so a dashboard request still in flight when the next step
# visits a page carries the pre-visit session and, finishing late, overwrites the cookie that
# redirect just set — dropping its flash ("Access Denied") or even the login. Only bites under
# parallel load, when those requests are slow.
def wait_for_page_to_settle
  # rack_test has no browser and no background requests
  return unless page.driver.respond_to?(:with_playwright_page)

  # Turbo marks a frame [busy] while it is fetching
  expect(page).to have_no_css("turbo-frame[busy]")
  page.driver.with_playwright_page do |pw_page|
    # No HTTP requests for 500 ms (ActionCable's websocket doesn't count)
    pw_page.wait_for_load_state(state: 'networkidle', timeout: Capybara.default_max_wait_time * 1000)
  rescue Playwright::TimeoutError
    # A page that polls never goes idle; carry on rather than fail the login
    nil
  end
end

When(/^I fill the password incorrectly and submit the login page$/) do
  fill_in('user_email', with: @user.email)
  fill_in('user_password', with: "Wrong pass")
  click_on("Log In")
  sleep(1)
end

When('I fill and submit the login without password') do
  fill_in('user_email_wo_pass', with: @user.email)
  sleep(5)
  click_on("Log In Via Email Link")
  sleep(2)
end


Then('when I click on the link in the email {string}') do |link|
  current_email.click_link link
end

When('I request a password reset') do
  visit("/users/password/new")
  fill_in('user_email', with: @user.email)
  click_on("Reset Password")
end

When('I click on the link in the email {string}') do |link|
  current_email.click_link link
end

When('I set my new password to {string}') do |new_password|
  fill_in('user_password', with: new_password)
  fill_in('user_password_confirmation', with: new_password)
  # The Reset Password submit input on this page uses type="Submit" (capital S),
  # which click_on's case-sensitive selector misses even though browsers treat it as submit.
  find(:xpath, "//input[@value='Reset Password']").click
end

Then('I should be able to log in with the password {string}') do |password|
  # Resetting the password signs the user in automatically, so log out first
  # to prove the new password (not the stale session) is what authenticates.
  steps %(Given I log out)
  visit("/users/sign_in")
  fill_in('user_email', with: @user.email)
  fill_in('user_password', with: password)
  click_on("Log In")
  expect(page).not_to have_current_path('/users/sign_in', wait: 15)
end

Given('I log out') do
  unless ui_login_required?
    # Scenarios here log out only to log in as someone else. Dropping the browser's cookies ends the
    # session just as Users::SessionsController#destroy would, without loading the dashboard and
    # clicking through the profile menu (whose header re-renders under the click - hence the old
    # sleep(2)). reset! also waits for the server's in-flight requests, so none can re-set the cookie.
    page.reset!
    next
  end

  visit("entities/dashboard")
  sleep(2)
  find("#profile_menu").click
  click_on("Log Out")
  click_on("Logout")
end

Given('I login as the investor user') do
  @user = @investor_user
  log_in(@user)
end

Given('I login as the portfolio company user') do
  @user = @portfolio_company.investor_entity.employees.first
  @user ||= FactoryBot.create(:user, entity: @portfolio_company.investor_entity)
  @user.add_role(:company_admin)
  log_in(@user)
end
