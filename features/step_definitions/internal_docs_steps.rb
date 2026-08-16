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

# Mirrors what UsersController#login_as leaves behind: the CUSTOMER's user record
# with the acting support user recorded on it. The customer does not hold the
# support role — User#support? returns true purely from support_user_id, which is
# exactly what InternalDocPolicy must not rely on.
Given('the user is impersonating a customer') do
  support_user = FactoryBot.create(:user, entity: @entity)
  support_user.add_role :support
  @user.update!(support_user_id: support_user.id)
  @user.reload
end

# Pins the premise of the scenario above: if this ever stops being true, the
# impersonation carve-out in InternalDocPolicy is testing nothing.
Then('the user should be treated as support by the legacy helper') do
  expect(@user.support?).to be(true)
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
