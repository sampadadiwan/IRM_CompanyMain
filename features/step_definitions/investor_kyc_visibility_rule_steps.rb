# Steps for: features/core/investor_kyc_visibility_rule.feature
# Worked examples V1-V11: openspec/changes/kyc-advisor-notification-delivery-fix/design.md#worked-examples

# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

Given('the user {string} has permission {string} disabled') do |email, permission|
  user = User.find_by!(email: email)
  user.permissions.unset(permission.to_sym)
  user.save!
end

# Turns a module off for a whole entity - user.enable_kycs reads the entity's flag as well as the
# user's own, so an advisor switched into this entity has enable_kycs false while they are in it.
Given('the entity {string} has KYCs disabled') do |entity_kv|
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  entity.permissions.unset(:enable_kycs)
  entity.save!
end

# Same as "the advisor ... is switched into entity ...", but with chosen allowed_roles - e.g. a
# company_admin grant (V8). The grant mirrors the user's own permissions, as that step does, so
# enable_kycs is on.
Given('the advisor {string} is switched into entity {string} with allowed_roles {string}') do |email, entity_kv, roles_csv|
  user   = User.find_by!(email: email)
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  ia = InvestorAdvisor.new(user:, entity:, email: user.email, allowed_roles: roles_csv.split(',').map(&:strip))
  # User.permissions is an active_flag definition, not a Hash - it has #keys but no #each_key.
  User.permissions.keys.each { |permission| ia.permissions.set(permission) } # rubocop:disable Style/HashEachMethods
  ia.save!
  ia.switch(user)
  user.reload
end

Given('the investor advisor grant for {string} on entity {string} has extended permission {string}') do |email, entity_kv, permission|
  grant = InvestorAdvisor.find_by!(user: User.find_by!(email: email), entity: Entity.find_by!(name: entity_kv.split('=').last))
  grant.extended_permissions.set(permission.to_sym)
  grant.save!
end

Given('the investor advisor grant for {string} on entity {string} has permission {string} disabled') do |email, entity_kv, permission|
  grant = InvestorAdvisor.find_by!(user: User.find_by!(email: email), entity: Entity.find_by!(name: entity_kv.split('=').last))
  grant.permissions.unset(permission.to_sym)
  grant.save!
end

# ─────────────────────────────────────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────────────────────────────────────

# The model call behind the investor's "Updates Required" button
# (InvestorKycsController#send_notification) - the button itself only adds a message param.
When('the investor clicks Updates Required on the KYC') do
  @investor_kyc.reload.updates_requested_notification
end

# Same Trailblazer step as "the investor submits an update to the KYC", but with NotifyKycJob on a
# test adapter so the job is recorded instead of run. The suite's inline adapter would otherwise
# run it immediately, and an inline send and a queued send would look identical from here.
When('the investor submits an update to the KYC with background jobs held') do
  @held_jobs_adapter = ActiveJob::QueueAdapters::TestAdapter.new
  previous_adapter = NotifyKycJob.queue_adapter
  NotifyKycJob.queue_adapter = @held_jobs_adapter
  begin
    result = InvestorKycUpdate.call(investor_kyc: @investor_kyc.reload, investor_user: true, validate: true)
    expect(result).to be_success
  ensure
    NotifyKycJob.queue_adapter = previous_adapter
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Assertions
# ─────────────────────────────────────────────────────────────────────────────

# The KYC list (InvestorKycPolicy::Scope) must agree with show? - the visibility rule is applied
# in one place and the page reads it from there.
Then('the investor kyc should be in the KYC list of {string}') do |email|
  user = User.find_by!(email: email)
  expect(Pundit.policy_scope!(user, InvestorKyc).exists?(id: @investor_kyc.id)).to be(true)
end

Then('the investor kyc should not be in the KYC list of {string}') do |email|
  user = User.find_by!(email: email)
  expect(Pundit.policy_scope!(user, InvestorKyc).exists?(id: @investor_kyc.id)).to be(false)
end

# InvestorKycMailer#notify_updates_requested's subject: "Action Required: Please update your KYC details".
Then('the user {string} receives a KYC updates requested notification email') do |email|
  eventually do
    mail = ActionMailer::Base.deliveries.find do |m|
      m.to.include?(email) && m.subject.to_s.include?('Please update your KYC')
    end
    expect(mail).to be_present
  end
end

Then('a NotifyKycJob is queued for the investor kyc with email_method {string}') do |email_method|
  jobs = @held_jobs_adapter.enqueued_jobs.select { |job| job[:job] == NotifyKycJob }
  # args are serialized: [investor_kyc_id, { "email_method" => ..., "msg" => ... }]
  match = jobs.find { |job| job[:args].first == @investor_kyc.id && job[:args].last["email_method"] == email_method }
  expect(match).to be_present
end
