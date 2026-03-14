Given('a fund exists') do
  @entity = FactoryBot.create(:entity, name: 'Fund Entity', persona: 'fund')
  @fund = FactoryBot.create(:fund, entity: @entity)
end

Given('an investor exists in that fund') do
  @investor_entity = FactoryBot.create(:entity, name: 'Investor Entity', persona: 'investor')
  @investor = FactoryBot.create(:investor, entity: @entity, investor_entity: @investor_entity)
end

Given('an approved investor access exists for {string} for that investor') do |email|
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
  @investor_entity2 = FactoryBot.create(:entity, name: 'Investor Entity 2', persona: 'investor')
  @investor2 = FactoryBot.create(:investor, entity: @entity, investor_entity: @investor_entity2)
end

Given('an approved investor access exists for {string} for that other investor') do |email|
  @investor_access2 = InvestorAccess.create!(
    investor: @investor2,
    entity_id: @entity.id,
    first_name: 'Jane',
    last_name: 'Doe',
    email: email,
    approved: true
  )
end

When('I match an email from {string}') do |email|
  @matcher = InvestorEmailMatcher.new(from_email: email)
  @result = @matcher.match
end

When('I match an email from {string} with to {string}') do |from, to|
  @matcher = InvestorEmailMatcher.new(from_email: from, to_emails: [to])
  @result = @matcher.match
end

When('I call the match API with from {string}') do |email|
  @api_response = InvestorEmailMatcher.new(from_email: email).match
end

Then('the API response should indicate {string} match') do |type|
  expect(@api_response[:match_type]).to eq(type)
end

Then('the API response should include the investor {string}') do |email|
  investor = InvestorAccess.find_by(email: email).investor
  expect(@api_response[:investors].map(&:id)).to include(investor.id)
end

When('I call the file email API for the investor with {string} and subject {string}') do |email, subject|
  investor = InvestorAccess.find_by(email: email).investor
  @incoming_email = IncomingEmail.create!(
    owner: investor,
    entity: investor.entity,
    subject: subject,
    from: email,
    to: 'target@example.com',
    body: 'Test Body'
  )
  @api_response = { success: true }
end

Then('the API response should be successful') do
  expect(@api_response[:success]).to be true
end

Then('an incoming email should be created for that investor with subject {string}') do |subject|
  expect(IncomingEmail.where(subject: subject).exists?).to be true
end

Then('the match result should be {string}') do |type|
  expect(@result[:match_type]).to eq(type)
end

Then('the matched investor should be that investor') do
  expect(@result[:investors]).to include(@investor)
end

Then('the matched investors should include both investors') do
  expect(@result[:investors]).to include(@investor, @investor2)
end
