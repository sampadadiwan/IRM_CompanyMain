# frozen_string_literal: true

# Starting and stopping the support machine, idle stop, and conversation usage —
# features/support_console/machine.feature. EC2 is SupportConsoleMachineStub.

HEALTH_URL = "#{SupportConsoleRelayStub::URL}/health".freeze

Given('the support machine is {string}') do |state|
  SupportConsoleMachineStub.reset!(state: state)
  # The relay answers once EC2 says running; the job and the badge check it the same way
  WebMock::API.stub_request(:get, HEALTH_URL).to_return(status: 200)
end

Given('the support machine is {string}, started {int} {word} ago') do |state, amount, unit|
  SupportConsoleMachineStub.reset!(state: state, launched: amount.public_send(unit).ago)
  WebMock::API.stub_request(:get, HEALTH_URL).to_return(status: 200)
end

# H9 — the first POST finds no relay (machine stopped); after the start, the retry is answered
Given('the relay is down until the machine starts, then answers {string}') do |text|
  WebMock::API.stub_request(:post, TURNS_URL).to_raise(Errno::ECONNREFUSED).then
              .to_return(status: 200, body: SupportConsoleRelayStub.answer(text))
end

# H10 — two answers with their token counts and costs
Given('the relay answers with {int} tokens costing {float} and then {int} tokens costing {float}') do |t1, c1, t2, c2|
  usage = ->(tokens) { { input: tokens - 100, output: 100, cache_read: 0, cache_write: 0 } }
  stub_relay_turns(SupportConsoleRelayStub.answer("First answer", usage: usage.call(t1), cost_usd: c1),
                   SupportConsoleRelayStub.answer("Second answer", usage: usage.call(t2), cost_usd: c2))
end

# The badge is lazy-loaded into the header; rack_test does not follow frames, so open it directly
When('I open the machine badge') do
  visit support_console_machine_status_path
end

When('I click the machine button {string}') do |id|
  click_button id
end

When('I post {string} to the machine') do |action|
  page.driver.submit :post, support_console_machine_path(action), {}
end

When('the idle check runs') do
  SupportConsoleIdleStopJob.perform_now
end

Then('the machine badge shows {string}') do |text|
  expect(page).to have_css("#support-console-machine-status", text: text)
end

Then('the support machine was sent {string}') do |call|
  expect(SupportConsoleMachineStub.calls).to include(call.to_sym)
end

Then('the relay was asked {int} time(s)') do |count|
  expect(relay_turn_signatures.size).to eq(count)
end

Then('the support machine was not sent anything') do
  expect(SupportConsoleMachineStub.calls).to be_empty
end

# H12, E38, X35 — no SUPPORT_CONSOLE_RELAY_URL: the app has to find the relay itself.
# The @support_console After hook restores the URL.
Given('the relay URL is not set') do
  ENV.delete("SUPPORT_CONSOLE_RELAY_URL")
end

Given('the support machine is {string} at {string}') do |state, ip|
  SupportConsoleMachineStub.reset!(state: state, ip: ip)
  WebMock::API.stub_request(:get, "http://#{ip}:4900/health").to_return(status: 200)
end

Given('the relay at {string} answers {string}') do |ip, text|
  WebMock::API.stub_request(:post, "http://#{ip}:4900/turns").to_return(status: 200, body: SupportConsoleRelayStub.answer(text))
end

Given('the relay at {string} answers {string} and {string}, then cannot be reached') do |ip, first, second|
  WebMock::API.stub_request(:post, "http://#{ip}:4900/turns")
              .to_return({ status: 200, body: SupportConsoleRelayStub.answer(first) },
                         { status: 200, body: SupportConsoleRelayStub.answer(second) }).then.to_raise(Errno::ECONNREFUSED)
end

# E38 — the test environment's cache is a null store; this scenario needs a real one
Given('found relay addresses are cached') do
  @previous_cache = Rails.cache
  Rails.cache = ActiveSupport::Cache::MemoryStore.new
end

After('@support_console') do
  Rails.cache = @previous_cache if @previous_cache
end

# E39 — another site's deployment (CURRENT_SITE), with SiteRegistry's memo cleared either side
When('the relay address is looked up for site {string}') do |code|
  previous = ENV.fetch("CURRENT_SITE", nil)
  ENV["CURRENT_SITE"] = code
  SiteRegistry.instance_variable_set(:@current_code, nil)
  SupportConsoleMachineControl.instance
ensure
  ENV["CURRENT_SITE"] = previous
  SiteRegistry.instance_variable_set(:@current_code, nil)
end

Then('the machine was looked up as {string}') do |name|
  expect(SupportConsoleMachineStub.lookups).to include(name)
  expect(SupportConsoleMachineStub.lookups.uniq).to eq([name])
end

Then('the machine was not looked up') do
  expect(SupportConsoleMachineStub.lookups).to be_empty
end

# E38 — two questions, one lookup: the second reused the cached address
Then('the machine was looked up {int} time(s)') do |count|
  expect(SupportConsoleMachineStub.lookups.size).to eq(count)
  @lookups_before = count
end

# E38 — the unreachable relay dropped the cached address, so EC2 was asked again
Then('the machine was looked up again') do
  expect(SupportConsoleMachineStub.lookups.size).to be > @lookups_before
end
