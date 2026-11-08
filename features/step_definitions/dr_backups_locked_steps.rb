# frozen_string_literal: true

# Steps for features/misc/dr_backups_locked.feature. Pure: lock configurations as plain hashes.

def dr_lock_config(state, mode = nil, days = nil)
  { enabled: state == "on", mode: mode, days: days }
end

When("the lock plan is made for a replica with Object Lock {string}") do |state|
  @dr_plan = Dr::BackupLock.plan(dr_lock_config(state))
end

When("the lock plan is made for a replica with Object Lock {string}, mode {string} and {int} days") do |state, mode, days|
  @dr_plan = Dr::BackupLock.plan(dr_lock_config(state, mode, days))
end

When("the lock plan is made for a replica with Object Lock {string} and no default retention") do |state|
  @dr_plan = Dr::BackupLock.plan(dr_lock_config(state))
end

Then("the plan is {string}") do |text|
  expect(@dr_plan[:summary]).to eq(text)
end

When("the replica lock is graded with Object Lock {string}, mode {string} and {int} days") do |state, mode, days|
  @dr_grade = Dr::BackupLock.grade("replica", dr_lock_config(state, mode, days))
end

When("the replica lock is graded with Object Lock {string}") do |state|
  @dr_grade = Dr::BackupLock.grade("replica", dr_lock_config(state))
end

Then("the lock grade is {string}") do |status|
  expect(@dr_grade.status).to eq(status.to_sym)
end

Then("the lock grade is {string} mentioning {string}") do |status, text|
  expect(@dr_grade.status).to eq(status.to_sym)
  expect(@dr_grade.detail).to include(text)
end

Given("the primary buckets {string} and {string}") do |a, b|
  @dr_primaries = [a, b]
end

Given("their replication destinations {string}, {string} and {string}") do |a, b, c|
  @dr_destinations = [a, b, c]
end

When("the buckets to lock are chosen") do
  @dr_targets = Dr::BackupLock.replicas_to_lock(primaries: @dr_primaries, destinations: @dr_destinations)
end

Then("they are {string} and {string}") do |a, b|
  expect(@dr_targets).to eq([a, b])
end

When("locking is asked for {string} with ALLOW_PRODUCTION {string}") do |env, allow|
  @dr_lock_allowed = Dr::BackupLock.env_allowed?(env, allow_production: allow == "1")
end

Then("locking is {string}") do |verdict|
  expect(@dr_lock_allowed).to eq(verdict == "allowed")
end

Given("a replication role policy that reads source versions without the lock permissions") do
  @dr_policy = { "Version" => "2012-10-17", "Statement" => [
    { "Effect" => "Allow", "Action" => %w[s3:GetReplicationConfiguration s3:ListBucket], "Resource" => ["arn:aws:s3:::src"] },
    { "Effect" => "Allow", "Action" => %w[s3:GetObjectVersionForReplication s3:GetObjectVersionAcl], "Resource" => ["arn:aws:s3:::src/*"] }
  ] }
end

When("the lock permissions are added") do
  @dr_policy = Dr::BackupLock.role_policy_with_lock_actions(@dr_policy)
end

Then("the reading statement includes {string} and {string}") do |a, b|
  reader = @dr_policy["Statement"].find { |st| st["Action"].include?("s3:GetObjectVersionForReplication") }
  expect(reader["Action"]).to include(a, b)
  expect(@dr_policy["Statement"].first["Action"]).not_to include(a)
end

Then("adding them again changes nothing") do
  expect(Dr::BackupLock.role_policy_with_lock_actions(@dr_policy)).to be_nil
end
