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
