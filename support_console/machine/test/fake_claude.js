#!/usr/bin/env node
// A stand-in for `claude -p --output-format stream-json`, for the relay's tests (CLAUDE_BIN).
// FAKE_CLAUDE_MODE: answer (default) | slow | db_error | fail | garbled | usage_limit | auth_expired. Records its argv (and, with
// FAKE_CLAUDE_ENV_FILE, its environment) for assertions.
import fs from "node:fs"

const mode = process.env.FAKE_CLAUDE_MODE || "answer"
if (process.env.FAKE_CLAUDE_ARGS_FILE) fs.writeFileSync(process.env.FAKE_CLAUDE_ARGS_FILE, JSON.stringify(process.argv.slice(2)))
if (process.env.FAKE_CLAUDE_ENV_FILE) fs.writeFileSync(process.env.FAKE_CLAUDE_ENV_FILE, JSON.stringify(process.env))

let question = ""
process.stdin.on("data", (c) => { question += c })
process.stdin.on("end", async () => {
  const out = (obj) => process.stdout.write(JSON.stringify(obj) + "\n")
  out({ type: "system", subtype: "init", session_id: "11111111-2222-3333-4444-555555555555" })
  out({ type: "assistant", message: { content: [{ type: "tool_use", name: "Grep", input: { pattern: "closing_balance" } }] } })

  if (mode === "db_error") {
    // What the db MCP server writes when it is not on a replica (X11).
    fs.appendFileSync(process.env.SUPPORT_EVENTS_FILE, JSON.stringify({ type: "error", code: "not_a_replica", message: "not_a_replica" }) + "\n")
    await new Promise((r) => setTimeout(r, 2000))
  }
  if (mode === "slow") await new Promise((r) => setTimeout(r, 30_000))
  // A torn line in the events file, as a crashed hook could leave.
  if (mode === "garbled") fs.appendFileSync(process.env.SUPPORT_EVENTS_FILE, "{\"type\": \"query\", \"sql\n")
  // What Claude Code reports when a subscription is out of usage (X28) or its token is dead (X29).
  if (mode === "usage_limit") {
    out({ type: "result", subtype: "error_during_execution", is_error: true, result: "You've hit your limit · resets 3pm (Asia/Kolkata)" })
    process.exit(1)
  }
  if (mode === "auth_expired") {
    out({ type: "result", subtype: "error_during_execution", is_error: true, result: "OAuth token has expired. Please run /login" })
    process.exit(1)
  }
  if (mode === "fail") {
    out({ type: "result", subtype: "error_during_execution", is_error: true, result: "boom" })
    process.exit(1)
  }

  out({ type: "assistant", message: { content: [{ type: "tool_use", name: "mcp__db__query", input: { sql: "SELECT 1" } }] } })
  // What the db MCP server writes for a lookup that ran.
  fs.appendFileSync(process.env.SUPPORT_EVENTS_FILE, JSON.stringify({ type: "query", sql: "SELECT 1", outcome: "ran", row_count: 3, duration_ms: 41, lag_seconds: 4, flagged: false }) + "\n")
  out({ type: "result", subtype: "success", is_error: false, result: `Answer to: ${question}`, session_id: "11111111-2222-3333-4444-555555555555", total_cost_usd: 0.12,
    usage: { input_tokens: 1200, output_tokens: 300, cache_read_input_tokens: 5000, cache_creation_input_tokens: 500 } })
})
