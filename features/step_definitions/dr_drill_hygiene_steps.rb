# frozen_string_literal: true

# Steps for features/misc/dr_drill_hygiene.feature. Pure: lock files, deploy files and the
# environment are given in memory - nothing reads S3, runs Pulumi or talks to a server.

# Pulumi lock content, as the S3 backend stores it (lowercase JSON keys)
def dr_lock_json(user:, host:, pid:, minutes_ago:)
  { "pid" => pid, "username" => user, "hostname" => host,
    "timestamp" => (Time.current - minutes_ago.minutes).iso8601 }.to_json
end

Given("a Pulumi lock by {string} on this machine with a live pid, taken {int} minutes ago") do |user, minutes|
  @dr_locks = [dr_lock_json(user: user, host: Socket.gethostname, pid: 4242, minutes_ago: minutes)]
  @dr_alive = ->(_pid) { true }
end

Given("a Pulumi lock by {string} on this machine with a dead pid, taken {int} minutes ago") do |user, minutes|
  @dr_locks = [dr_lock_json(user: user, host: Socket.gethostname, pid: 4242, minutes_ago: minutes)]
  @dr_alive = ->(_pid) { false }
end

Given("a Pulumi lock by {string} on host {string}, taken {int} minutes ago") do |user, host, minutes|
  @dr_locks = [dr_lock_json(user: user, host: host, pid: 4242, minutes_ago: minutes)]
  @dr_alive = ->(_pid) { true }
end

When("the Pulumi locks for {string} are classified from no lock files") do |stack|
  @dr_lock = Dr::PulumiLock.classify([], stack: stack, local_host: Socket.gethostname, alive: ->(_pid) { false })
end

When("the Pulumi locks for {string} are classified") do |stack|
  @dr_lock = Dr::PulumiLock.classify(@dr_locks, stack: stack, local_host: Socket.gethostname, alive: @dr_alive)
end

Then("the stack lock state is {string}") do |state|
  expect(@dr_lock.state).to eq(state.to_sym)
end

Then("the lock message mentions {string}") do |text|
  expect(@dr_lock.message).to include(text)
end

Given("a deploy file naming servers {string} and {string}") do |ip1, ip2|
  # The shape of config/deploy/staging_in.rb: one `server "<ip>", ...` line per role set
  @dr_deploy_file = <<~RUBY
    server "#{ip1}", user: "ubuntu", roles: %w[app web] if ENV["LB"]
    server "#{ip2}", user: "ubuntu", roles: %w[primary app web db]
  RUBY
end

When("it is checked against the drill servers {string} and {string}") do |ip1, ip2|
  @dr_targets_drill = Dr::DrillTeardown.targets_drill?(@dr_deploy_file, [ip1, ip2])
end

Then("the deploy file targets the drill") do
  expect(@dr_targets_drill).to be(true)
end

Then("the deploy file does not target the drill") do
  expect(@dr_targets_drill).to be(false)
end

When("the error mail prefix is built for {string} on {string} with DR_DRILL_STACK {string}") do |rails_env, domain, region|
  env = region.empty? ? {} : { "DR_DRILL_STACK" => region }
  @dr_prefix = DrillStack.email_prefix(rails_env: rails_env, base_domain: domain, env: env)
end

Then("the error mail prefix is {string}") do |prefix|
  expect(@dr_prefix).to eq(prefix)
end

Given("critical WhatsApp alerts are switched on") do
  CriticalErrorWhatsapp.enabled = true
end

When("DR_DRILL_STACK is {string}") do |region|
  @dr_saved_drill_stack = ENV.fetch("DR_DRILL_STACK", nil)
  ENV["DR_DRILL_STACK"] = region
  @dr_whatsapp_enabled = CriticalErrorWhatsapp.send(:enabled?)
ensure
  # Never leak the flag or the override into other scenarios
  ENV["DR_DRILL_STACK"] = @dr_saved_drill_stack
  CriticalErrorWhatsapp.enabled = nil
end

Then("critical WhatsApp alerts are not enabled") do
  expect(@dr_whatsapp_enabled).to be(false)
end
