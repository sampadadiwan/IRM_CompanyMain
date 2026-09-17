# frozen_string_literal: true

# Step definitions for features/security/internal_docs_access.feature
#
# These drive ActionDispatch::Integration::Session rather than Capybara. Two
# reasons: the assertions are about status codes and redirect targets rather
# than rendered UI, and the traversal scenarios need to put a literal ".." on
# the wire — a browser would normalise it away client-side and the request
# under test would never reach Rails.

# Roles are added before signing in so the session is built from a user who
# already holds them, matching how a real staff account arrives.
Given('the user has the role {string}') do |role|
  @user.add_role role.to_sym
  @user.reload
end

# :super cannot go through add_role — User#forbid_bad_role throws :abort with
# "Cannot add super role to a user", so it is a break-glass role granted by
# writing the join row by hand. InternalDocPolicy must still honour it, hence
# this setup writes the row the same way. The SQL is plain enough to run on both
# SQLite (test) and MySQL (dev/prod).
Given('the user has the super role granted directly in the database') do
  role = Role.find_or_create_by!(name: "super")
  sql  = ActiveRecord::Base.sanitize_sql_array(
    ["INSERT INTO users_roles (user_id, role_id) VALUES (?, ?)", @user.id, role.id]
  )
  ActiveRecord::Base.connection.execute(sql)
  @user.reload
end

# Drives the REAL impersonation flow through UsersController#login_as rather than
# writing support_user_id on a model in this process. That shortcut would prove
# nothing: support_user_id is an attr_accessor, not a column (user.rb:25), and
# WithAuthentication#authenticate_user! reassigns it from session[:support_user_id]
# on every request, so the request under test would see nil and deny for the
# ordinary "no staff role" reason — passing even if InternalDocPolicy were
# rewritten to use User#support?, the exact regression this guards against.
When('a support user impersonates the user and requests {string}') do |path|
  support_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
  support_user   = FactoryBot.create(:user, entity: support_entity)
  support_user.add_role :support

  # UserPolicy#login_as? needs an enabled mapping for the target's entity whose
  # login-as whitelist admits the acting user; a blank user_emails list means
  # "any support user", so enable_user_login alone carries it.
  FactoryBot.create(:support_client_mapping,
                    user: support_user, entity: @user.entity,
                    enabled: true, enable_user_login: true)

  @docs_session = ActionDispatch::Integration::Session.new(Rails.application)
  @docs_session.post "/users/sign_in", params: { user: { email: support_user.email, password: "password" } }
  @docs_session.post "/users/#{@user.id}/login_as"
  @docs_session.get path
end

# Pins the premise of the scenario: without this the request could be denied
# because impersonation silently failed to start, and the carve-out under test
# would never be exercised.
Then('the impersonation should be active in the session') do
  expect(@docs_session.session[:support_user_id]).to be_present
end

When('the user requests {string}') do |path|
  @docs_session = ActionDispatch::Integration::Session.new(Rails.application)
  @docs_session.post "/users/sign_in", params: { user: { email: @user.email, password: "password" } }
  @docs_session.get path
end

When('an anonymous visitor requests {string}') do |path|
  @docs_session = ActionDispatch::Integration::Session.new(Rails.application)
  @docs_session.get path
end

Then('the docs response should be successful') do
  # Report where a redirect went — "expected 200, got 302" alone does not say
  # whether the policy denied the request or the document was not found.
  expect(@docs_session.response.status).to eq(200),
                                           "expected 200, got #{@docs_session.response.status} " \
                                           "(location: #{@docs_session.response.location.inspect})"
end

# Compares only the path so a scheme/host on the Location header (Devise emits a
# full URL) does not make the expectation brittle.
Then('the docs response should redirect to {string}') do |expected_path|
  expect(@docs_session.response.status).to be_between(300, 399),
                                           "expected a redirect, got #{@docs_session.response.status}"
  expect(URI.parse(@docs_session.response.location).path).to eq(expected_path)
end

Then('the docs response body should contain {string}') do |text|
  expect(@docs_session.response.body).to include(text)
end
