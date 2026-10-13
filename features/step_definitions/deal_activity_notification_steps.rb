Given('the investor {string} has an approved user {string}') do |investor_name, email|
  investor = Investor.find_by!(investor_name: investor_name)
  user = User.find_by(email: email) || FactoryBot.create(:user, email: email, entity: investor.investor_entity)

  InvestorAccess.find_or_create_by!(
    investor: investor,
    user: user,
    entity_id: investor.entity_id,
    email: email
  ) do |ia|
    ia.first_name = user.first_name
    ia.last_name = user.last_name
    ia.approved = true
  end

  # Grant access to the deal so notification_users(deal) includes this user
  AccessRight.find_or_create_by!(
    owner: @deal,
    entity_id: @deal.entity_id,
    access_to_investor_id: investor.id
  )
end

Then('a deal notification email should be sent to {string} with subject {string}') do |email, subject|
  open_email(email)
  expect(current_email.subject).to include(subject)
end

Then('an email should be sent to the current user with subject {string}') do |subject|
  # Recipient should be the company admin (usually @user in these tests)

  open_email(@user.email)
  expect(current_email.subject).to include(subject)
end

Given('there is a startup entity') do
  @entity = FactoryBot.create(:entity, entity_type: "Startup")
end

Given('there is a user for the entity') do
  @user = FactoryBot.create(:user, entity: @entity)
  @user.add_role(:company_admin)
end

Given('I am logged in') do
  steps %(
    And I am signed in as the current user
  )
end

Given('there exists a deal {string} for company') do |arg1|
  @deal = FactoryBot.build(:deal, entity: @entity)
  key_values(@deal, arg1)
  CreateDeal.call(deal: @deal).success?.should
  puts "\n####Deal####\n"
  puts @deal.to_json
end

Given('the deal is started and has an investor {string}') do |investor_name|
  @deal.update!(start_date: Time.zone.today)

  @another_entity = FactoryBot.create(:entity, name: investor_name, entity_type: "Investor")
  random_pan = Faker::Alphanumeric.alphanumeric(number: 10, min_alpha: 3)
  @investor = Investor.create!(
    investor_name: @another_entity.name,
    investor_entity: @another_entity,
    entity: @entity,
    pan: random_pan,
    primary_email: @another_entity.primary_email,
    category: "Lead Investor"
  )

  @deal_investor = DealInvestor.create!(
    investor: @investor,
    entity: @entity,
    deal: @deal,
    status: "Active"
  )
  # Generate activities for the investor
  @deal_investor.create_activities

  # Set the initial activity
  first_template = @deal.deal_activities.templates(@deal).first
  @deal_investor.update!(deal_activity_id: first_template.id)
end

Given('the deal has enable notifications set') do
  @deal.update!(json_fields: (@deal.json_fields || {}).merge("enable_notifications" => "1"))
end

Given('the deal activity {string} has {string} enabled') do |title, flag|
  # This finds the template activity for the deal
  activity = @deal.deal_activities.find_by(title: title, deal_investor_id: nil)
  puts "Activity template not found for: #{title}. Available activities: #{@deal.deal_activities.templates(@deal).pluck(:title).join(', ')}" if activity.nil?
  activity.update!(flag.to_sym => true)

  # Also update the instance for the current deal investor if it exists
  if @deal_investor
    instance = @deal_investor.deal_activities.find_by(template_id: activity.id)
    instance&.update!(flag.to_sym => true)
  end
end

When('I move the deal investor {string} to stage {string}') do |investor_name, stage_title|
  @deal_investor = @deal.deal_investors.joins(:investor).find_by(investors: { investor_name: investor_name })
  target_activity_template = @deal.deal_activities.find_by(title: stage_title, deal_investor_id: nil)

  # Find the current activity instance for this investor
  current_activity = @deal_investor.deal_activities.find_by(template_id: @deal_investor.deal_activity_id)

  # Simulate the move via the service
  PerformActivityAction.call(
    deal_investor: @deal_investor,
    deal_activity: current_activity,
    initial_deal_activity_id: @deal_investor.deal_activity_id,
    target_deal_activity_id: target_activity_template.id,
    user_id: @user.id
  )
end

Given('there is a custom notification for the deal with method {string} and tag {string} and subject {string}') do |method, tag, subject|
  CustomNotification.create!(
    entity: @deal.entity,
    owner: @deal,
    email_method: method,
    tag: tag,
    subject: subject,
    body: "Custom body for #{tag}",
    enabled: true
  )
end

Given('there is a custom notification for the deal with method {string} and subject {string}') do |method, subject|
  CustomNotification.create!(
    entity: @deal.entity,
    owner: @deal,
    email_method: method,
    subject: subject,
    body: "Generic move body",
    enabled: true
  )
end

Given('there is a custom notification with placeholders for the deal with method {string} and subject {string}') do |method, subject|
  CustomNotification.create!(
    entity: @deal.entity,
    owner: @deal,
    email_method: method,
    subject: subject,
    body: "Deal {{deal_name}} moved, investor {{investor_name}}. Unknown: {{not_a_real_placeholder}}.",
    enabled: true
  )
end

Then('the deal notification placeholders are resolved correctly') do
  open_email(@user.email)
  expect(current_email).not_to be_nil
  body = current_email.body.to_s

  # Known DealMailer placeholders resolved
  expect(body).not_to include("{{deal_name}}")
  expect(body).not_to include("{{investor_name}}")
  expect(body).to include(@deal.name)

  # Unknown placeholder preserved
  expect(body).to include("{{not_a_real_placeholder}}")
end

# Variant of 'the investor ... has an approved user ...' that also sets a tag_list
# on the InvestorAccess so tag-based notification filtering can be tested.
Given('the investor {string} has an approved user {string} with tag_list {string}') do |investor_name, email, tag|
  investor = Investor.find_by!(investor_name: investor_name)
  user = User.find_by(email: email) || FactoryBot.create(:user, email: email, entity: investor.investor_entity)

  ia = InvestorAccess.find_or_initialize_by(
    investor: investor,
    user: user,
    entity_id: investor.entity_id,
    email: email
  )
  ia.assign_attributes(
    first_name: user.first_name,
    last_name: user.last_name,
    approved: true,
    tag_list: tag
  )
  ia.save!

  AccessRight.find_or_create_by!(
    owner: @deal,
    entity_id: @deal.entity_id,
    access_to_investor_id: investor.id
  )
end

Then('no deal notification email should be sent to {string}') do |email|
  matching = emails_sent_to(email).select { |m| m.subject.to_s.include?("Deal Update:") }
  expect(matching).to be_empty,
                      "Expected no deal notification email to #{email} but found: #{matching.map(&:subject)}"
end
