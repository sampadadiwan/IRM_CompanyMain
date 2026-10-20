#!/usr/bin/env node
// Claude Code PreToolUse hook for mcp__db__query (design card ⑥).
// Reads the hook input JSON on stdin. Exit 0 lets the call run; exit 2 blocks it and Claude Code
// shows the stderr text to Claude, which then retries with the filter (design walkthrough row 5).
import { checkStatement } from "../lib/sql_rules.js"
import { appendEvent } from "../lib/events.js"
import { tablesWithEntityId, loadJoinMap } from "../lib/tables.js"

let input = ""
process.stdin.on("data", (chunk) => { input += chunk })
process.stdin.on("end", () => {
  let payload
  try {
    payload = JSON.parse(input)
  } catch {
    // Unreadable hook input: refuse rather than let an unchecked lookup through.
    process.stderr.write("Lookup refused: the scope check could not read the request.")
    process.exit(2)
  }

  const sql = payload?.tool_input?.sql ?? ""
  const entityId = process.env.SUPPORT_ENTITY_ID
  // E13, E14, E16 — the rules shared with the db MCP server.
  const reason = checkStatement(sql, entityId, tablesWithEntityId(), null, loadJoinMap())
  if (!reason) process.exit(0)

  appendEvent({ sql: sql || "(no statement)", outcome: "blocked", reason })
  const help = {
    "add filter": `Every table with an entity_id column must be filtered with entity_id = ${entityId}.`,
    "other client": `This conversation is only about entity_id ${entityId}.`,
    "SELECT only": "Only a single read-only SELECT (or WITH … SELECT) is allowed.",
    "table not allowed": "That table is not readable from the Support Console.",
    "unreadable": "The statement could not be checked; write it as a plain SELECT.",
  }[reason] ?? (reason.startsWith("join on a real relationship") ? "Join it along that foreign key, from a table filtered on the client." : "")
  process.stderr.write(`Lookup refused (${reason}). ${help}`)
  process.exit(2)
})
