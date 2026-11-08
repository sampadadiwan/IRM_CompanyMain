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

When("a drill run is verified on servers with DR_DRILL_STACK {string}") do |region|
  @dr_grade = DrillStack.grade_mark(expected_drill: true, env: region.empty? ? {} : { "DR_DRILL_STACK" => region })
end

When("a real recovery is verified on servers with DR_DRILL_STACK {string}") do |region|
  @dr_grade = DrillStack.grade_mark(expected_drill: false, env: region.empty? ? {} : { "DR_DRILL_STACK" => region })
end

Then("the drill mark grade is {string} mentioning {string}") do |status, text|
  expect(@dr_grade.status).to eq(status.to_sym)
  expect(@dr_grade.detail).to include(text)
end

Given("a drill log with a row for {string}") do |branch|
  @dr_log = <<~MD
    # DR Drill Log

    | Date | Stack | Variant | Region | Result | Rebuild (min) | Branch |
    |---|---|---|---|---|---|---|
    | 2026-09-12 18:32 | staging | in | ap-south-2 | FAILED | 5.0 | dr_drill_in_2026_09_12_1832 |
    | 2026-11-08 10:39 | staging | in | ap-south-2 | PASSED | 12.1 | #{branch} |
  MD
end

When("the teardown {string} is recorded for {string}") do |cell, branch|
  @dr_log = Dr::DrillTeardown.add_teardown_cell(@dr_log, branch, cell)
end

Then("the drill log header ends with {string}") do |ending|
  expect(@dr_log.lines.find { |l| l.start_with?("| Date |") }.rstrip).to end_with(ending)
  # The separator row gains a column too, or the table breaks
  expect(@dr_log.lines.find { |l| l.start_with?("|---") }.rstrip.count("|")).to eq(9)
end

Then("the row for {string} ends with {string}") do |branch, ending|
  expect(@dr_log.lines.find { |l| l.include?("| #{branch} |") }.rstrip).to end_with(ending)
end

When("the teardown is summarised for a {string} run with teardown {string}, stop {string} and destroyed {string}") do |result, teardown, stop, destroyed|
  destroyed_value = { "" => nil, "failed" => :failed }.fetch(destroyed) { destroyed.to_i }
  @dr_cell = Dr::DrillTeardown.summary(passed: result == "passed", teardown: teardown == "yes",
                                       stop: stop.empty? ? nil : stop.to_sym, destroyed: destroyed_value)
end

Then("the teardown cell reads {string}") do |cell|
  expect(@dr_cell).to eq(cell)
end

When("the DR drill code is exercised in a process that loads only the Rakefile") do
  # Exactly what `rake aws:dr_drill` has before it touches AWS: the Rakefile loaded, Rails
  # defined but NOT initialized. Then every Dr:: path the drill reaches, with no network.
  script = <<~RUBY
    require "rake"
    Rake.application.init("rake", [])
    Rake.application.load_rakefile
    abort "RAILS_INITIALIZED" if Rails.application.initialized?
    Dr::PulumiLock.classify([], stack: "s", local_host: Socket.gethostname, alive: ->(_) { false })
    Dr::BackupSchedule.drill?({ "DR_DRILL" => "true" })
    Dr::DrillTeardown.add_teardown_cell("| Date | Branch |\\n|---|---|\\n| x | b |\\n", "b",
                                        Dr::DrillTeardown.summary(passed: true, teardown: true, stop: :stopped, destroyed: 1))
    DrillStack.grade_mark(expected_drill: true, env: { "DR_DRILL_STACK" => "r" })
    t = Time.utc(2026, 11, 8)
    m = Dr::ReportModel.build(phases: [["Phase 1/9 · Refresh Pulumi stack configuration", t, t + 3]],
                              scorecard: { "h" => [["✅", "Nginx active — active"]] }, evidence: {}, result: "PASSED",
                              stack: "staging", region: "r", env_variant: "in", branch: "b", started_at: t, finished: t + 9,
                              drill: true, teardown: true, executed_by: "x")
    Dr::ReportRender.html(m)
    Dr::ReportRender.markdown(m)
    puts "DR_CODE_OK"
  RUBY
  @dr_out, @dr_status = Open3.capture2e({ "RAILS_ENV" => "test" }, "bundle", "exec", "ruby", "-e", script, chdir: Rails.root.to_s)
end

Then("that process succeeds without initializing Rails") do
  expect(@dr_out).not_to include("RAILS_INITIALIZED")
  expect(@dr_status.success?).to be(true), @dr_out.lines.last(15).join
  expect(@dr_out).to include("DR_CODE_OK")
end

Given("pulumi destroy printed {string} and a summary of {int} deleted") do |resource_line, count|
  @dr_destroy_output = " -  #{resource_line} \n@ destroying....\nResources:\n    - #{count} deleted\n\nDuration: 2m57s\n"
end

When("the destroyed count is read") do
  @dr_destroyed = Dr::DrillTeardown.destroyed_count(@dr_destroy_output)
end

Then("the destroyed count is {int}") do |count|
  expect(@dr_destroyed).to eq(count)
end

When("the Pulumi login record says current is {string}") do |url|
  @dr_backend = Dr::PulumiLock.backend_from_credentials({ current: url, accessTokens: {} }.to_json)
end

When("the Pulumi login record is {string}") do |record|
  @dr_backend = Dr::PulumiLock.backend_from_credentials(record)
end

Then("the current backend is {string}") do |url|
  expect(@dr_backend).to eq(url)
end

Then("the current backend is unknown") do
  expect(@dr_backend).to be_nil
end
