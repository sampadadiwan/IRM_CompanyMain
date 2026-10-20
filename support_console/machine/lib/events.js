// Per-turn events file: the hook and the db MCP server append one JSON line per lookup; the relay
// tails it, numbers each event and forwards it to Rails as a `query` event (design card ④).
import fs from "node:fs"

export function appendEvent(event) {
  const file = process.env.SUPPORT_EVENTS_FILE
  if (!file) return
  fs.appendFileSync(file, JSON.stringify({ type: "query", ...event }) + "\n")
}

// X11, X12 — a machine-side failure that must end the turn (the relay forwards it and stops Claude).
export function appendError(code, message) {
  const file = process.env.SUPPORT_EVENTS_FILE
  if (!file) return
  fs.appendFileSync(file, JSON.stringify({ type: "error", code, message }) + "\n")
}
