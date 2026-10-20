# frozen_string_literal: true

# A scripted stand-in for the relay on the support machine (design card ④), for
# features/support_console/. Scenarios tagged @support_console point the Rails side at
# SupportConsoleRelayStub::URL; @sync-http turns WebMock on so the stubs below answer.
module SupportConsoleRelayStub
  URL = "http://support-relay.test"
  SECRET = "test-relay-secret"

  module_function

  # @return [String] NDJSON for a completed turn
  def answer(text, claude_session_id: "cs-1", lag_seconds: 4, code_rev: "425c604a1b2c3d4e5f60718293a4b5c6d7e8f901",
             progress: ["Reading how closing balance is calculated"], queries: [], usage: nil, cost_usd: 0.12)
    events = progress.map { |line| { type: "progress", text: line } }
    events += queries.each_with_index.map { |q, i| { type: "query", seq: i + 1, code_rev: code_rev }.merge(q) }
    # The text arrives in pieces, as Claude Code streams it.
    events += text.scan(/.{1,20}/m).map { |piece| { type: "text", delta: piece } }
    events << { type: "result", claude_session_id: claude_session_id, code_rev: code_rev, lag_seconds: lag_seconds,
                cost_usd: cost_usd, usage: usage }.compact
    ndjson(events)
  end

  # @return [String] NDJSON for a machine-side failure
  def error(code, message = "failed")
    ndjson([{ type: "error", code: code, message: message }])
  end

  def ndjson(events)
    events.map(&:to_json).join("\n") << "\n"
  end
end

Before("@support_console") do
  @previous_relay_env = ENV.to_h.slice("SUPPORT_CONSOLE_RELAY_URL", "SUPPORT_CONSOLE_RELAY_SECRET")
  ENV["SUPPORT_CONSOLE_RELAY_URL"] = SupportConsoleRelayStub::URL
  ENV["SUPPORT_CONSOLE_RELAY_SECRET"] = SupportConsoleRelayStub::SECRET
end

After("@support_console") do
  %w[SUPPORT_CONSOLE_RELAY_URL SUPPORT_CONSOLE_RELAY_SECRET].each { |key| ENV[key] = @previous_relay_env[key] }
end
