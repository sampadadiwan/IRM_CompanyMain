# Steps for: features/core/investor_access_tag_notifications.feature
# Tests subscription-based tag filtering on InvestorAccess#tag_list.
# Subscription semantics: no tag = subscribed to all; tag present = subscribed only to matching topics.

# ─────────────────────────────────────────────────────────────────────────────
# PRIVATE HELPER
# ─────────────────────────────────────────────────────────────────────────────

# Maps the notification_type label used in feature step text to an email subject fragment.
# "approval"    → "Approval required:" (from ApprovalMailer#notify_approval)
# "KYC"         → "Request to add KYC:" (from InvestorKycMailer#notify_kyc_required)
# "CapitalCall" → fund name (from CapitalRemittanceMailer: "fund_name: call_name")
def notification_subject_for(notification_type)
  case notification_type
  when "approval"              then "Approval required:"
  when "KYC"                   then "Request to add KYC:"
  when "CapitalCall"           then @fund.name  # "FundName: CapitalCallName" from notify_capital_remittance
  when "CapitalRemittance"     then "#{@fund.name}:"  # same mailer subject: "FundName: CapitalCallName"
  when "Distribution"          then "Capital Distribution:"  # from send_notification mailer
  when "InvestmentOpportunity" then "Investment Opportunity:"  # from notify_open_for_interests mailer
  when "SecondarySale"         then "Interest received for"
  else notification_type
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# DATA SETUP
# ─────────────────────────────────────────────────────────────────────────────

# Creates an InvestorKyc for @investor with the given key=value args.
# Always fires the employee "KYC updated" notification so scenario 3 (employee path)
# can assert on it independently of the investor notification path.
Given('a KYC is created for the investor with {string}') do |args|
  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @entity, investor: @investor)
  key_values(@investor_kyc, args)
  # investor_user: false → admin-created path (triggers send_kyc_form_on_create when flag=true)
  InvestorKycCreate.wtf?(investor_kyc: @investor_kyc, investor_user: false).success?.should == true
  # Explicitly fire employee "KYC updated" notification — mirrors the path InvestorKycAction takes
  # when investor_user=true, here fired unconditionally to prove the employee path is tag-independent.
  @investor_kyc.updated_notification
  puts "\n####InvestorKyc####\n"
  puts @investor_kyc.to_json
end

# Creates an investor advisor InvestorAccess for @investor with the given tag_list.
# The advisor lives in a separate entity (their advisory firm) and holds the :investor_advisor role,
# which causes InvestorAccess#is_investor_advisor to be set to true on save.
Given('there is an investor advisor with tag_list {string} for the investor') do |tag|
  ia_entity = FactoryBot.create(:entity, entity_type: "Investor")
  @ia_user = FactoryBot.create(:user, entity: ia_entity)
  @ia_user.add_role(:investor_advisor)
  @investor_advisor_access = InvestorAccess.create!(
    investor: @investor,
    user: @ia_user,
    entity_id: @investor.entity_id,
    first_name: @ia_user.first_name,
    last_name: @ia_user.last_name,
    email: @ia_user.email,
    approved: true,
    tag_list: tag
  )
  puts "\n####Investor Advisor Access####\n"
  puts @investor_advisor_access.to_json
end

# ─────────────────────────────────────────────────────────────────────────────
# CAPITAL CALL — HEADLESS CREATION AND APPROVAL
# ─────────────────────────────────────────────────────────────────────────────

# Headless capital call creation — avoids browser UI so no login session is needed.
# Uses key_values to apply semicolon-separated attr=val pairs, same as other headless steps.
When('a capital call is created with {string}') do |args|
  @capital_call = FactoryBot.build(:capital_call, fund: @fund, entity: @fund.entity)
  key_values(@capital_call, args)
  @capital_call.setup_defaults
  result = CapitalCallCreate.wtf?(capital_call: @capital_call)
  puts result
  result.success?.should == true
  @capital_call.reload
  puts "\n####CapitalCall####\n"
  puts @capital_call.to_json
end

# Headless capital call approval — mirrors the existing "when the capital call is approved" step
# but matches the plain "the capital call is approved" text used in the feature.
When('the capital call is approved') do
  @capital_call.approved = true
  @capital_call.approved_by_user = @user
  result = CapitalCallApprove.wtf?(capital_call: @capital_call)
  puts result
  result.success?.should == true
  @capital_call.reload
  # saved_change_to_approved? is reset by generate_capital_remittances' internal save;
  # call notify_capital_call directly so notification fires regardless of dirty-tracking state.
  @capital_call.notify_capital_call
end

# ─────────────────────────────────────────────────────────────────────────────
# EMAIL ASSERTIONS — GENERIC INVESTOR CONTACT (uses @investor_access)
# ─────────────────────────────────────────────────────────────────────────────

# Generic receives/skips assertion. outcome is "receives" or "skips".
Then('the investor contact {string} the {string} notification') do |outcome, notification_type|
  email_address = @investor_access.email
  subject_fragment = notification_subject_for(notification_type)
  matching = emails_sent_to(email_address).select { |m| m.subject.to_s.include?(subject_fragment) }

  if outcome == "receives"
    expect(matching).not_to be_empty,
      "Expected #{email_address} to receive '#{notification_type}' notification " \
      "(subject includes '#{subject_fragment}') but none found. " \
      "Deliveries to this address: #{emails_sent_to(email_address).map(&:subject)}"
  else
    expect(matching).to be_empty,
      "Expected #{email_address} to skip '#{notification_type}' notification " \
      "but found: #{matching.map(&:subject)}"
  end
end

# "investor notification" variant used in KYC domain steps where the step text has "investor" appended.
Then('the investor contact {string} the {string} investor notification') do |outcome, notification_type|
  steps %(Then the investor contact "#{outcome}" the "#{notification_type}" notification)
end

# Explicit "does not receive" variant used in Scenario 3 where the step text is longer.
Then('the investor contact does not receive the {string} investor notification') do |notification_type|
  email_address = @investor_access.email
  subject_fragment = notification_subject_for(notification_type)
  matching = emails_sent_to(email_address).select { |m| m.subject.to_s.include?(subject_fragment) }
  expect(matching).to be_empty,
    "Expected #{email_address} NOT to receive '#{notification_type}' investor notification " \
    "but found: #{matching.map(&:subject)}"
end

# ─────────────────────────────────────────────────────────────────────────────
# EMAIL ASSERTIONS — NAMED INVESTOR CONTACT (Scenario 2: mixed tags)
# ─────────────────────────────────────────────────────────────────────────────

Then('the {string} investor contact receives the {string} notification') do |firm_name, notification_type|
  investor = Investor.find_by!(investor_name: firm_name)
  email_address = investor.investor_accesses.approved.first.email
  subject_fragment = notification_subject_for(notification_type)
  matching = emails_sent_to(email_address).select { |m| m.subject.to_s.include?(subject_fragment) }
  expect(matching).not_to be_empty,
    "Expected #{firm_name} (#{email_address}) to receive '#{notification_type}' notification " \
    "but none found. Deliveries: #{emails_sent_to(email_address).map(&:subject)}"
end

Then('the {string} investor contact does not receive the {string} notification') do |firm_name, notification_type|
  investor = Investor.find_by!(investor_name: firm_name)
  email_address = investor.investor_accesses.approved.first.email
  subject_fragment = notification_subject_for(notification_type)
  matching = emails_sent_to(email_address).select { |m| m.subject.to_s.include?(subject_fragment) }
  expect(matching).to be_empty,
    "Expected #{firm_name} (#{email_address}) to skip '#{notification_type}' notification " \
    "but found: #{matching.map(&:subject)}"
end

# ─────────────────────────────────────────────────────────────────────────────
# EMAIL ASSERTIONS — EMPLOYEE
# ─────────────────────────────────────────────────────────────────────────────

# Checks the first active employee received the given notification type.
# "KYC updated" maps to subject "KYC updated for <full_name>" (InvestorKycMailer#notify_kyc_updated).
Then('the employee receives the {string} employee notification') do |notification_type|
  employee = @entity.employees.active.first
  subject_fragment = case notification_type
                     when "KYC updated" then "KYC updated for"
                     else notification_type
                     end
  matching = emails_sent_to(employee.email).select { |m| m.subject.to_s.include?(subject_fragment) }
  expect(matching).not_to be_empty,
    "Expected employee #{employee.email} to receive '#{notification_type}' email " \
    "(subject includes '#{subject_fragment}') but none found. " \
    "Deliveries: #{emails_sent_to(employee.email).map(&:subject)}"
end

# ─────────────────────────────────────────────────────────────────────────────
# EMAIL ASSERTIONS — INVESTOR ADVISOR
# ─────────────────────────────────────────────────────────────────────────────

Then('the investor advisor {string} the {string} notification') do |outcome, notification_type|
  email_address = @investor_advisor_access.email
  subject_fragment = notification_subject_for(notification_type)
  matching = emails_sent_to(email_address).select { |m| m.subject.to_s.include?(subject_fragment) }

  if outcome == "receives"
    expect(matching).not_to be_empty,
      "Expected investor advisor #{email_address} to receive '#{notification_type}' notification " \
      "but none found. Deliveries: #{emails_sent_to(email_address).map(&:subject)}"
  else
    expect(matching).to be_empty,
      "Expected investor advisor #{email_address} to skip '#{notification_type}' notification " \
      "but found: #{matching.map(&:subject)}"
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# DISTRIBUTION — SETUP AND TRIGGER
# ─────────────────────────────────────────────────────────────────────────────

# Creates an approved capital distribution plus a completed payment for @investor's commitment.
# send_notification_on_complete and manual_generation both have safe DB defaults (true/false),
# so no explicit flags needed; force: true bypasses the notification_sent guard.
Given('there is an approved capital distribution for the fund') do
  @capital_distribution = FactoryBot.create(:capital_distribution,
    fund: @fund,
    entity: @fund.entity,
    approved: true
  )
  # CDPs are auto-generated inline (CapitalDistributionJob runs via :inline adapter in tests).
  # Just mark the investor's payment as completed so send_notification's inner condition passes.
  @capital_distribution.capital_distribution_payments
    .where(investor: @investor)
    .update_all(completed: true)
  puts "\n####CapitalDistribution####\n"
  puts @capital_distribution.to_json
end

When('the distribution payment notification is sent') do
  @capital_distribution.capital_distribution_payments.each do |cdp|
    cdp.send_notification(force: true)
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# CAPITAL REMITTANCE — TRIGGER
# send_call_notice_flag defaults to true in the DB, so no override needed.
# ─────────────────────────────────────────────────────────────────────────────

When('the capital remittance notification is sent') do
  @capital_call.capital_remittances.each do |cr|
    cr.send_notification
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# INVESTMENT OPPORTUNITY — TRIGGER
# ─────────────────────────────────────────────────────────────────────────────

When('the investment opportunity open notification is sent') do
  @investment_opportunity.notify_open_for_interests
end

# ─────────────────────────────────────────────────────────────────────────────
# SECONDARY SALE / INTEREST — SETUP AND TRIGGER
# ─────────────────────────────────────────────────────────────────────────────

Given('there is a secondary sale for the entity') do
  @secondary_sale = FactoryBot.create(:secondary_sale, entity: @entity)
  puts "\n####SecondarySale####\n"
  puts @secondary_sale.to_json
end

# Builds the Interest directly rather than going through the full verified flow,
# since we only need to test notification routing, not the interest creation validations.
Given('there is an interest from the investor in the secondary sale') do
  @interest = Interest.new(
    secondary_sale: @secondary_sale,
    investor: @investor,
    entity: @entity,
    interest_entity: @investor.investor_entity,
    short_listed_status: 'pending',
    quantity: 100,
    price: 100
  )
  @interest.save!(validate: false)
  puts "\n####Interest####\n"
  puts @interest.to_json
end

When('the interest notification is sent') do
  @interest.notify_interest
end
