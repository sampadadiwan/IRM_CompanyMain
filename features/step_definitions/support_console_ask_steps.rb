# frozen_string_literal: true

# Asking, streaming and stopping — features/support_console/ask.feature.
# The relay is SupportConsoleRelayStub (features/support/support_console_relay_stub.rb).

TURNS_URL = "#{SupportConsoleRelayStub::URL}/turns".freeze
STOP_URL = "#{SupportConsoleRelayStub::URL}/turns/current".freeze

# Each stubbed turn answers in order; the last one repeats.
def stub_relay_turns(*bodies)
  responses = bodies.map { |body| body.is_a?(Hash) ? body : { status: 200, body: body } }
  WebMock::API.stub_request(:post, TURNS_URL).to_return(*responses)
  WebMock::API.stub_request(:delete, STOP_URL).to_return(status: 204)
end

# @return [Array<Hash>] the parsed bodies Rails posted to /turns
def relay_turn_requests
  relay_turn_signatures.map { |sig| JSON.parse(sig.body) }
end

# WebMock normalises URIs (adds :80), so match on host and path.
#
# @return [Array<WebMock::RequestSignature>] the POSTs Rails made to /turns, in order
def relay_turn_signatures
  relay = URI(SupportConsoleRelayStub::URL)
  WebMock::RequestRegistry.instance.requested_signatures.hash.keys
                          .select { |sig| sig.method == :post && sig.uri.host == relay.host && sig.uri.path == "/turns" }
end

Given('the relay answers {string}') do |text|
  stub_relay_turns(SupportConsoleRelayStub.answer(text))
end

Given('the relay answers {string} with Claude session {string}') do |text, session_id|
  stub_relay_turns(SupportConsoleRelayStub.answer(text, claude_session_id: session_id))
end

Given('the relay answers {string} and then {string}') do |first, second|
  stub_relay_turns(SupportConsoleRelayStub.answer(first, claude_session_id: "cs-first"),
                   SupportConsoleRelayStub.answer(second, claude_session_id: "cs-second"))
end

Given('the relay answers {string} with replica lag {int} seconds') do |text, lag|
  stub_relay_turns(SupportConsoleRelayStub.answer(text, lag_seconds: lag))
end

Given('the relay answers {string} on code version {string} and then {string} on code version {string}') do |t1, rev1, t2, rev2|
  stub_relay_turns(SupportConsoleRelayStub.answer(t1, code_rev: rev1), SupportConsoleRelayStub.answer(t2, code_rev: rev2))
end

Given('the relay answers {string} after a denied Bash attempt') do |text|
  stub_relay_turns(SupportConsoleRelayStub.answer(text, progress: ["Tool denied: Bash"]))
end

Given('the relay says a turn is already running') do
  stub_relay_turns({ status: 409, body: "" })
end

Given('the relay fails with status {int}') do |status|
  stub_relay_turns({ status: status, body: "" })
end

Given('the relay is unreachable') do
  WebMock::API.stub_request(:post, TURNS_URL).to_raise(Errno::ECONNREFUSED)
end

Given('the relay stream goes quiet') do
  WebMock::API.stub_request(:post, TURNS_URL).to_raise(Net::ReadTimeout)
  WebMock::API.stub_request(:delete, STOP_URL).to_return(status: 204)
end

Given('the relay reports the error {string}') do |code|
  stub_relay_turns(SupportConsoleRelayStub.error(code))
end

When('I ask {string}') do |question|
  fill_in "support-console-question", with: question
  click_button "Ask"
end

When('I ask a question of {int} characters') do |length|
  fill_in "support-console-question", with: "a" * length
  click_button "Ask"
end

When('I press Ask with an empty question') do
  fill_in "support-console-question", with: ""
  click_button "Ask"
end

Then('I see the answer {string}') do |text|
  within("#support-console-messages") { expect(page).to have_content(text) }
end

Then('I see no answer') do
  expect(AgentChatMessage.where(role: "assistant").count).to eq(0)
end

Then('the footer shows {string}') do |text|
  expect(page).to have_css("#support-console-footer", text: text)
end

Then('the footer is highlighted as a warning') do
  expect(page).to have_css("#support-console-footer.text-danger")
end

Then('the footer is not highlighted') do
  expect(page).to have_no_css("#support-console-footer.text-danger")
  expect(page).to have_css("#support-console-footer")
end

Then('the question box contains {string}') do |text|
  expect(find_field("support-console-question").value).to eq(text)
end

Then('the relay was asked to resume Claude session {string}') do |session_id|
  expect(relay_turn_requests.last["resume_id"]).to eq(session_id)
end

Then('the first turn did not resume any session') do
  expect(relay_turn_requests.first["resume_id"]).to be_nil
end

Then('the brief sent to the relay names only {string}') do |entity_name|
  brief = relay_turn_requests.last["brief"]
  entity = support_console_entity(entity_name)
  expect(brief).to include("#{entity.name} (entity_id #{entity.id})")
  (@support_console_entities.values - [entity]).each { |other| expect(brief).not_to include(other.name) }
  expect(relay_turn_requests.last["entity_id"]).to eq(entity.id)
end

Then('the brief sent to the relay says {string}') do |text|
  expect(relay_turn_requests.last["brief"]).to include(text)
end

Then('the turn was sent only to this environment\'s relay, correctly signed') do
  signature = relay_turn_signatures.first
  expect(signature).to be_present
  timestamp = signature.headers["X-Timestamp"]
  expected = OpenSSL::HMAC.hexdigest("SHA256", SupportConsoleRelayStub::SECRET, "#{timestamp}.POST./turns.#{signature.body}")
  expect(signature.headers["X-Signature"]).to eq(expected)
end

Then('the relay was asked to stop the turn') do
  WebMock::API.assert_requested(:delete, STOP_URL)
end

Then('the relay was not called') do
  WebMock::API.assert_not_requested(:post, TURNS_URL)
end

# While a turn runs the composer's send button becomes Stop, so there is no Ask to press.
Then('Stop replaces Ask') do
  expect(page).to have_button("Stop")
  expect(page).to have_no_button("Ask")
end

Then('Ask is enabled') do
  expect(page).to have_button("Ask", disabled: false)
  expect(page).to have_no_button("Stop")
end

# A conversation whose latest turn is still running — for Stop (E9) and double submits (E4).
Given('{string} has a conversation about {string} with a turn still running') do |first_name, entity_name|
  user = @support_console_users.fetch(first_name)
  @running_session = AgentChatSession.create!(support_agent: SupportConsoleAgent.record, analyst: user,
                                              chattable: support_console_entity(entity_name), channel: "web", status: "active")
  @running_session.agent_chat_messages.create!(role: "user", content: "Why is the balance zero?", channel: "web")
  @running_message = @running_session.agent_chat_messages.create!(role: "assistant", content: "Working…", channel: "web",
                                                                  metadata: { "turn_status" => "running" })
  WebMock::API.stub_request(:delete, STOP_URL).to_return(status: 204)
end

When('I open that conversation') do
  visit support_console_entity_path(@running_session.chattable, session_id: @running_session.id)
end

When('I press Stop') do
  click_button "Stop"
end

When('I post a question to that conversation directly') do
  page.driver.submit :post, support_console_turns_path(@running_session.chattable),
                     { session_id: @running_session.id, question: "Second question" }
end

Given('{string} has {int} conversations about {string} started on {string}') do |first_name, _count, entity_name, dates|
  user = @support_console_users.fetch(first_name)
  dates.split(",").map(&:strip).each do |date|
    time = Date.parse(date).in_time_zone.change(hour: 10)
    session = AgentChatSession.create!(support_agent: SupportConsoleAgent.record, analyst: user, chattable: support_console_entity(entity_name),
                                       channel: "web", status: "active", created_at: time, updated_at: time)
    session.agent_chat_messages.create!(role: "user", content: "Question from #{date}", channel: "web", created_at: time)
  end
end

Then('the conversations are listed newest first as {string}') do |questions|
  rows = all("#support-console-conversations [data-role='first-question']").map(&:text)
  expect(rows).to eq(questions.split(",").map(&:strip))
end

# E8 — the mapping changes between the question being queued and the job running.
Given("{string} has a queued question about {string}") do |first_name, entity_name|
  user = @support_console_users.fetch(first_name)
  session = AgentChatSession.create!(support_agent: SupportConsoleAgent.record, analyst: user,
                                     chattable: support_console_entity(entity_name), channel: "web", status: "active")
  session.agent_chat_messages.create!(role: "user", content: "Why is the balance zero?", channel: "web")
  @queued_message = session.agent_chat_messages.create!(role: "assistant", content: "Working…", channel: "web",
                                                        metadata: { "turn_status" => "queued" })
end

When('the queued turn runs') do
  SupportConsoleTurnJob.perform_now(@queued_message.id)
end

Then('the queued turn is refused with {string}') do |text|
  @queued_message.reload
  expect(@queued_message.metadata["turn_status"]).to eq("refused")
  expect(@queued_message.content).to include(text)
end

When('I post a question about {string} directly') do |entity_name|
  page.driver.submit :post, support_console_turns_path(support_console_entity(entity_name)), { question: "Show me everything" }
end

When("I open {string}'s conversation about {string} through {string}") do |first_name, other_entity, entity_name|
  user = @support_console_users.fetch(first_name)
  other = AgentChatSession.create!(support_agent: SupportConsoleAgent.record, analyst: user,
                                   chattable: support_console_entity(other_entity), channel: "web", status: "active")
  visit support_console_entity_path(support_console_entity(entity_name), session_id: other.id)
end

Then('no support console messages were created') do
  expect(AgentChatMessage.count).to eq(0)
end

# E25 — every Turbo broadcast raises, as it did for a Sidekiq without the new helper.
Given('live updates fail to render') do
  allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(ActionView::MissingTemplate.new([], "x", [], false, "x"))
end

When('I open the Support Console for {string} conversation again') do |entity_name|
  session = AgentChatSession.where(chattable: support_console_entity(entity_name)).order(:id).last
  visit support_console_entity_path(session.chattable, session_id: session.id)
end

Then('the last turn is completed') do
  expect(AgentChatMessage.where(role: "assistant").order(:id).last.metadata["turn_status"]).to eq("completed")
end

Given('that running turn started {int} minutes ago') do |minutes|
  @running_message.update_columns(created_at: minutes.minutes.ago)
end

# E29, E31 — the model chosen per question.
When('I choose the model {string}') do |label|
  select label, from: "support-console-model"
end

Then('the model selector shows {string}') do |label|
  expect(page).to have_select("support-console-model", selected: label)
end

Then('the relay was asked to use {string}') do |name|
  expect(relay_turn_requests.last["model"]).to eq(name)
end

Then('the answer is labelled {string}') do |label|
  expect(all("[data-role='model']").last.text).to include(label)
end

When('I post a question about {string} directly with the model {string}') do |entity_name, model|
  page.driver.submit :post, support_console_turns_path(support_console_entity(entity_name)), { question: "Why?", model: model }
end

# X23 — a follow-up another support user queued in Meera's conversation.
Given("{string} has a queued follow-up in {string}'s conversation about {string}") do |asker_name, starter_name, entity_name|
  asker = @support_console_users.fetch(asker_name)
  session = AgentChatSession.create!(support_agent: SupportConsoleAgent.record, analyst: @support_console_users.fetch(starter_name),
                                     chattable: support_console_entity(entity_name), channel: "web", status: "active")
  session.agent_chat_messages.create!(role: "user", content: "And for Q4?", channel: "web", metadata: { "asked_by_id" => asker.id })
  @queued_message = session.agent_chat_messages.create!(role: "assistant", content: "Working…", channel: "web",
                                                        metadata: { "turn_status" => "queued", "asked_by_id" => asker.id })
end

# X24 — nothing in an answer loads by itself.
Then('the answer shows no image') do
  within("#support-console-messages") { expect(page).to have_no_css("img") }
end

Then('the answer links to {string} in a new tab') do |href|
  within("#support-console-messages") do
    expect(page).to have_css("a[href='#{href}'][target='_blank'][rel~='noopener']")
  end
end

# X25 — the machine sends the session id, then the stream ends without a result (a stop or a crash).
Given('the relay starts Claude session {string} and then the stream ends') do |claude_session_id|
  stub_relay_turns(SupportConsoleRelayStub.ndjson([{ type: "session", claude_session_id: claude_session_id },
                                                   { type: "progress", text: "Reading the code" }]))
end

Then('the last turn records Claude session {string}') do |claude_session_id|
  expect(AgentChatMessage.where(role: "assistant").order(:id).last.metadata["claude_session_id"]).to eq(claude_session_id)
end

# X26 — queued long ago, picked up by a job only recently.
Given('that running turn was queued {int} minutes ago and started {int} minutes ago') do |queued, started|
  @running_message.update_columns(created_at: queued.minutes.ago,
                                  metadata: @running_message.metadata.merge("started_at" => started.minutes.ago.iso8601))
end

# X28, X29 — which machine failures alert the team.
Given('error reports are watched') do
  @error_reports = []
  allow(ErrorReport).to receive(:notify) { |error, **_context| @error_reports << error.message }
end

Then('no error report was sent') do
  expect(@error_reports).to be_empty
end

Then('an error report says {string}') do |text|
  expect(@error_reports).to include(a_string_including(text))
end
