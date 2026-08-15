# Steps for the shared mail add-in API used by the Outlook task pane and the Gmail add-on.
#
# The API scenarios drive real HTTP requests through the full middleware stack via
# ActionDispatch::Integration::Session, rather than calling services directly. The previous
# version of this file asserted against a hash the step itself had just constructed:
#
#   @incoming_email = IncomingEmail.create!(...)
#   @api_response = { success: true }
#   ...
#   expect(@api_response[:success]).to be true
#
# No request was made and the scenario could not fail.

# ---------------------------------------------------------------- fixtures

# entity_type is pinned on every entity these scenarios create. The factory defaults it to
# `Entity::TYPES[rand(Entity::TYPES.length)]`, and one of the nine values is "Group
# Company" — which sends BaseScope#resolve down `where(entity_id: user.entity.child_ids)`
# instead of `where(entity_id: user.entity_id)`. A fund with no children then has an empty
# policy scope, so tier-1 contact matching silently finds nothing and the matcher falls
# through to tier 2. That made any scenario distinguishing the two tiers fail roughly one
# run in five, with no hint that a random fixture value was the cause.
Given('a fund exists') do
  @entity = FactoryBot.create(:entity, name: 'Fund Entity', persona: 'fund', entity_type: 'Investment Fund')
  @fund = FactoryBot.create(:fund, entity: @entity)
  @user = FactoryBot.create(:user, entity: @entity)
  @user.add_role(:company_admin)
end

Given('an investor exists in that fund') do
  @investor_entity = FactoryBot.create(:entity, name: 'Investor Entity', persona: 'investor',
                                                entity_type: 'Investor')
  @investor = FactoryBot.create(:investor, entity: @entity, investor_entity: @investor_entity)
end

Given('an approved investor access exists for {string} for that investor') do |email|
  # Set the primary email BEFORE creating the access: once the access links a
  # user, primary_email is locked (primary_email_locked_when_users_exist)
  @investor.update!(primary_email: email)
  @investor_access = InvestorAccess.create!(
    investor: @investor,
    entity_id: @entity.id,
    first_name: 'John',
    last_name: 'Doe',
    email: email,
    approved: true
  )
end

Given('another investor exists in that fund') do
  @investor_entity2 = FactoryBot.create(:entity, name: 'Investor Entity 2', persona: 'investor',
                                                 entity_type: 'Investor')
  @investor2 = FactoryBot.create(:investor, entity: @entity, investor_entity: @investor_entity2)
end

Given('that other investor has primary_email {string}') do |email|
  @investor2.update!(primary_email: email)
end

Given('that other investor is named {string}') do |name|
  @investor2.update!(investor_name: name)
end

# One person holding approved access to several investor records. InvestorAccess only
# permits that for an investor_advisor: ensure_entity_id otherwise pins a user to the one
# investor entity they belong to. So this promotes the existing user to advisor first,
# which is what makes the multi-record case reachable at all.
Given('an approved investor access exists for {string} for that other investor') do |email|
  advisor = User.find_by(email: email)
  advisor.add_role(:investor_advisor)
  # has_cached_role? reads a cached set populated on load; without this the validation
  # still sees the pre-promotion roles and rejects the record.
  advisor.reload

  InvestorAccess.create!(
    investor: @investor2,
    entity_id: @entity.id,
    first_name: 'Ada',
    last_name: 'Advisor',
    email: email,
    approved: true
  )
end

# ---------------------------------------------------------------- matcher

When('I match an email from {string}') do |email|
  @result = InvestorEmailMatcher.new(from_email: email, user: @user).match
end

# These go through the API rather than the matcher, because the matcher no longer has
# to_emails/cc_emails parameters at all. The clients still send them — they are stored on
# the filed record — so the assertion worth making is that the endpoint accepts them and
# they change nothing.
When('I call the mail API match endpoint for {string} with cc {string}') do |from, cc|
  mail_api.post('/api/v1/mail/match',
                params: { from_email: from, cc_emails: [cc] }.to_json,
                headers: mail_api_headers)
end

When('I call the mail API match endpoint for {string} with to {string}') do |from, to|
  mail_api.post('/api/v1/mail/match',
                params: { from_email: from, to_emails: [to] }.to_json,
                headers: mail_api_headers)
end

# The mailbox address is what the add-in host reports (Office userProfile / Session active
# user), and is normally a different string from the CapHive login.
When('I match an email from {string} read from mailbox {string}') do |from, mailbox|
  @result = InvestorEmailMatcher.new(from_email: from, mailbox_email: mailbox, user: @user).match
end

Then('the match result should be {string}') do |type|
  expect(@result[:match_type]).to eq(type)
end

Then('the matched investor should be that investor') do
  expect(@result[:investors]).to include(@investor)
end

Then('the matched investor should be that other investor') do
  expect(@result[:investors]).to include(@investor2)
end

# ---------------------------------------------------------------- API helpers

# In-process integration session: exercises routing, the token authentication filter and
# Pundit exactly as a real request would, without needing a running Capybara server.
def mail_api
  @mail_api ||= ActionDispatch::Integration::Session.new(Rails.application)
end

def mail_api_headers
  headers = { 'CONTENT_TYPE' => 'application/json', 'ACCEPT' => 'application/json' }
  headers['Authorization'] = "Bearer #{@mail_token}" if @mail_token
  headers
end

def mail_api_body
  JSON.parse(mail_api.response.body)
rescue JSON::ParserError
  {}
end

def file_email_via_api(subject, message_id)
  mail_api.post('/api/v1/mail/filings',
                params: {
                  owner_id: @investor.id,
                  subject: subject,
                  body: '<p>Body</p>',
                  from: 'john@example.com',
                  to: ['manager@fund.com'],
                  cc_emails: [],
                  internet_message_id: message_id,
                  received_at: Time.current.iso8601
                }.to_json,
                headers: mail_api_headers)
end

Given('I have a mail add-in token') do
  @mail_token = MailAddinToken.issue_for(@user).token
end

Given('I have an invalid mail add-in token') do
  @mail_token = 'not-a-real-token'
end

# Doorkeeper's default scope is `read` and other integrations issue tokens against the
# same server, so the mail API must reject anything not minted for the add-ins.
Given('I have a token issued to a different OAuth application') do
  other_app = Doorkeeper::Application.create!(
    name: 'Some Other Client', redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
    scopes: 'read', confidential: true
  )
  @mail_token = Doorkeeper::AccessToken.create!(
    application: other_app, resource_owner_id: @user.id, scopes: 'read',
    expires_in: 3600, use_refresh_token: false, entity_id: @user.entity_id
  ).token
end

Given('that investor has primary_email {string}') do |email|
  @investor.update!(primary_email: email)
end

# Materialises the second filing's folder so the undo actually exercises the cascade —
# without this the row has a NULL document_folder_id and the scenario would pass trivially.
Given("that filing shares the first filing's document folder") do
  email = IncomingEmail.find(@last_filing_id)
  email.document_folder
  expect(email.reload.document_folder_id).to eq(@shared_folder_id)
end

Given('that filing has an attached document') do
  email = IncomingEmail.find(@last_filing_id)
  # Goes through the real attachment path rather than building a Document by hand, so the
  # document lands in the shared folder exactly as a filed attachment would.
  upload = Rack::Test::UploadedFile.new(Rails.public_path.join('sample_uploads/signature.png'), 'image/png')
  failures = email.save_uploaded_attachments([upload], user: @user)
  expect(failures).to be_empty

  @shared_document = email.documents.reload.last
  # Guard the premise: the scenario is only meaningful if a shared folder actually exists.
  expect(email.reload.document_folder_id).to be_present
  @shared_folder_id = email.document_folder_id
end

# ---------------------------------------------------------------- API requests

When('I call the mail API match endpoint without a token') do
  @mail_token = nil
  mail_api.post('/api/v1/mail/match',
                params: { from_email: 'john@example.com' }.to_json,
                headers: mail_api_headers)
end

When('I call the mail API match endpoint for {string}') do |email|
  mail_api.post('/api/v1/mail/match',
                params: { from_email: email }.to_json,
                headers: mail_api_headers)
end

When('I call the mail API match endpoint for {string} with message id {string}') do |email, message_id|
  mail_api.post('/api/v1/mail/match',
                params: { from_email: email, internet_message_id: message_id }.to_json,
                headers: mail_api_headers)
end

# Cucumber matches on the phrase, not the keyword, so this serves both the Given and the
# When forms — defining it twice makes every use ambiguous.
When('I file an email with subject {string} and message id {string}') do |subject, message_id|
  file_email_via_api(subject, message_id)
  @last_filing_id = mail_api_body['id']
end

When('I file an email with subject {string} and no message id') do |subject|
  mail_api.post('/api/v1/mail/filings',
                params: {
                  owner_id: @investor.id, subject: subject, body: '<p>Body</p>',
                  from: 'john@example.com', to: ['manager@fund.com'],
                  received_at: Time.current.iso8601
                }.to_json,
                headers: mail_api_headers)
  @last_filing_id = mail_api_body['id']
end

When('I undo that filing') do
  mail_api.delete("/api/v1/mail/filings/#{@last_filing_id}", headers: mail_api_headers)
end

When('I search the mail API owners endpoint for {string}') do |query|
  mail_api.get("/api/v1/mail/owners?q=#{CGI.escape(query)}", headers: mail_api_headers)
end

# ---------------------------------------------------------------- API assertions

Then('the mail API response status should be {int}') do |status|
  expect(mail_api.response.status).to eq(status)
end

Then('the mail API match type should be {string}') do |type|
  expect(mail_api_body['match_type']).to eq(type)
end

Then('the mail API candidates should include that investor') do
  expect(mail_api_body['candidates'].pluck('id')).to include(@investor.id)
end

Then('the mail API candidate reason should be {string}') do |reason|
  expect(mail_api_body['candidates'].first['reason']).to eq(reason)
end

Then('the mail API response should report the email was already filed') do
  expect(mail_api_body['already_filed']).to be true
end

Then('the mail API response should not report the email was already filed') do
  expect(mail_api_body['already_filed']).to be_falsey
end

Then('the first filing should still have its document') do
  expect(Document.exists?(@shared_document.id)).to be true
  expect(Folder.exists?(@shared_folder_id)).to be true
end

Then('the mail API response should say the email is already filed') do
  expect(mail_api_body.dig('filed', 'filed')).to be true
end

Then('the already filed response should name that investor') do
  expect(mail_api_body.dig('filed', 'owner_name')).to eq(@investor.investor_name)
end

Then('the mail API owners response should include {string}') do |name|
  expect(mail_api_body['owners'].pluck('name')).to include(name)
end

Then('the mail API owners response should not include that investor') do
  expect(mail_api_body['owners'].pluck('id')).not_to include(@investor.id)
end

# ---------------------------------------------------------------- records

Then('an incoming email should be created for that investor with subject {string}') do |subject|
  expect(IncomingEmail.exists?(subject: subject, owner: @investor)).to be true
end

Then('the filed email should record who filed it') do
  email = IncomingEmail.where(owner: @investor).order(:id).last
  expect(email.filed_by_user_id).to eq(@user.id)
  expect(email.entity_id).to eq(@investor.entity_id)
end

Then('only {int} incoming email should exist with message id {string}') do |count, message_id|
  expect(IncomingEmail.where(internet_message_id: message_id).count).to eq(count)
end

Then('no incoming email should exist with message id {string}') do |message_id|
  expect(IncomingEmail.exists?(internet_message_id: message_id)).to be false
end

Then('filing should be gated on view permission and not on update permission') do
  policy = InvestorPolicy.new(@user, @investor)

  # Asserted against the policy directly rather than through a read-only employee fixture:
  # constructing one means entity permission bitmasks plus an AccessRight row, and a fixture
  # that elaborate tends to assert more about the fixture than about the rule. What matters
  # here is the rule itself — file_mail? follows show?, and a user who cannot update the
  # investor can still file against it.
  allow(policy).to receive(:show?).and_return(true)
  allow(policy).to receive(:update?).and_return(false)
  expect(policy.file_mail?).to be true

  allow(policy).to receive(:show?).and_return(false)
  expect(policy.file_mail?).to be false
end
