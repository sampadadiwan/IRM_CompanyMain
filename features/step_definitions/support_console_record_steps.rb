# frozen_string_literal: true

# Query record, alerts and retention — features/support_console/query_record.feature and retention.feature.

Given('the relay answers {string} after these lookups:') do |text, table|
  queries = table.hashes.map do |row|
    {
      sql: row.fetch("sql"),
      outcome: row.fetch("outcome"),
      reason: row["reason"].presence,
      row_count: row["row_count"].presence&.to_i,
      duration_ms: 41,
      lag_seconds: 4,
      flagged: row["flagged"] == "yes"
    }
  end
  stub_relay_turns(SupportConsoleRelayStub.answer(text, queries: queries))
end

Then('{int} support console query/queries is/are recorded') do |count|
  expect(SupportConsoleQuery.count).to eq(count)
end

Then('a support console query is recorded for {string} about {string} with outcome {string} and {int} rows') do |first_name, entity_name, outcome, rows|
  query = SupportConsoleQuery.find_by!(outcome: outcome)
  expect(query.user).to eq(@support_console_users.fetch(first_name))
  expect(query.entity).to eq(support_console_entity(entity_name))
  expect(query.row_count).to eq(rows)
  expect(query.duration_ms).to eq(41)
  expect(query.sql_text).to be_present
  expect(query.agent_chat_session).to be_present
end

Then('a support console query is recorded as {string} because {string}') do |outcome, reason|
  expect(SupportConsoleQuery.where(outcome: outcome).pluck(:reason)).to include(reason)
end

Then('the support console query is flagged') do
  expect(SupportConsoleQuery.flagged.count).to eq(1)
end

Then('the super user {string} has {int} flagged-lookup alert(s)') do |first_name, count|
  user = @support_console_users.fetch(first_name)
  alerts = Noticed::Notification.where(recipient: user).joins(:event)
                                .where(noticed_events: { type: "SupportConsoleQueryFlaggedNotifier" })
  expect(alerts.count).to eq(count)
end

Then('the support user {string} has no flagged-lookup alerts') do |first_name|
  user = @support_console_users.fetch(first_name)
  expect(Noticed::Notification.where(recipient: user).count).to eq(0)
end

When('the same lookup event is recorded again') do
  query = SupportConsoleQuery.last
  event = { "seq" => query.event_seq, "sql" => query.sql_text, "outcome" => query.outcome,
            "flagged" => query.flagged, "code_rev" => query.code_rev }
  @rerecorded = SupportConsoleQuery.record_event!(event, message: query.agent_chat_message)
end

Then('nothing new is recorded') do
  expect(@rerecorded).to be_nil
end

When('I open the Support Console query list') do
  visit admin_support_console_queries_path
end

When('I open the flagged Support Console queries') do
  visit admin_support_console_queries_path(flagged: true)
end

# Retention (E20)
Given('{string} has a conversation about {string} last active {int} days ago with Claude session {string}') do |first_name, entity_name, days, claude_id|
  user = @support_console_users.fetch(first_name)
  time = days.days.ago
  session = AgentChatSession.create!(support_agent: SupportConsoleAgent.record, analyst: user, chattable: support_console_entity(entity_name),
                                     channel: "web", status: "active", created_at: time, updated_at: time)
  session.agent_chat_messages.create!(role: "user", content: "Question #{days} days ago", channel: "web", created_at: time)
  message = session.agent_chat_messages.create!(role: "assistant", content: "Answer #{days} days ago", channel: "web", created_at: time,
                                                metadata: { "turn_status" => "completed", "claude_session_id" => claude_id })
  SupportConsoleQuery.create!(user: user, entity: session.chattable, agent_chat_session: session, agent_chat_message: message,
                              event_seq: 1, sql_text: "SELECT 1", outcome: "ran", code_rev: "425c604", created_at: time)
  session.update_columns(updated_at: time)
  WebMock::API.stub_request(:delete, "#{SupportConsoleRelayStub::URL}/transcripts").to_return(status: 204)
end

When('the Support Console retention runs') do
  SupportConsoleRetentionJob.perform_now
end

Then('the conversation with {string} is gone') do |question|
  expect(AgentChatMessage.where(content: question)).to be_none
end

Then('the conversation with {string} is kept') do |question|
  expect(AgentChatMessage.where(content: question)).to exist
end

Then('the machine was asked to delete transcript {string}') do |claude_id|
  WebMock::API.assert_requested(:delete, "#{SupportConsoleRelayStub::URL}/transcripts") { |req| JSON.parse(req.body)["claude_session_id"] == claude_id }
end

Then('the machine was not asked to delete transcript {string}') do |claude_id|
  WebMock::API.assert_not_requested(:delete, "#{SupportConsoleRelayStub::URL}/transcripts") { |req| JSON.parse(req.body)["claude_session_id"] == claude_id }
end

Then('{int} support console queries remain, {int} of them detached from any conversation') do |total, detached|
  expect(SupportConsoleQuery.count).to eq(total)
  expect(SupportConsoleQuery.where(agent_chat_session_id: nil).count).to eq(detached)
end

Given('a turn about {string} has been running for {int} minutes') do |entity_name, minutes|
  user = @support_console_users.values.first
  time = minutes.minutes.ago
  session = AgentChatSession.create!(support_agent: SupportConsoleAgent.record, analyst: user, chattable: support_console_entity(entity_name),
                                     channel: "web", status: "active")
  @stale_message = session.agent_chat_messages.create!(role: "assistant", content: "Working…", channel: "web", created_at: time,
                                                       metadata: { "turn_status" => "running" })
end

Then('that turn is closed with {string}') do |text|
  @stale_message.reload
  expect(@stale_message.metadata["turn_status"]).to eq("failed")
  expect(@stale_message.content).to eq(text)
end

Given('the relay cannot delete transcripts') do
  WebMock::API.stub_request(:delete, "#{SupportConsoleRelayStub::URL}/transcripts").to_raise(Errno::ECONNREFUSED)
end

# X23 — a conversation another support user will follow up in ("I open that conversation").
Given('{string} has a conversation about {string} with a finished answer') do |first_name, entity_name|
  user = @support_console_users.fetch(first_name)
  @running_session = AgentChatSession.create!(support_agent: SupportConsoleAgent.record, analyst: user,
                                              chattable: support_console_entity(entity_name), channel: "web", status: "active")
  @running_session.agent_chat_messages.create!(role: "user", content: "Why is the balance zero?", channel: "web",
                                               metadata: { "asked_by_id" => user.id })
  @running_session.agent_chat_messages.create!(role: "assistant", content: "No Q3 entries.", channel: "web",
                                               metadata: { "turn_status" => "completed", "asked_by_id" => user.id,
                                                           "claude_session_id" => "cs-meera" })
end

Then('the question {string} is labelled with {string}') do |question, first_name|
  bubble = find("#support-console-messages .sc-question", text: question)
  expect(bubble[:title]).to start_with(@support_console_users.fetch(first_name).full_name)
end
