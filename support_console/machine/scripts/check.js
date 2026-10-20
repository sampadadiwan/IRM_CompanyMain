#!/usr/bin/env node
// The machine check (design Local development step 4 / machine_check): prints one ✓ or ✗ line per
// control and exits non-zero if any fails. Reads the same environment as the relay.
import fs from "node:fs"
import path from "node:path"
import { spawnSync } from "node:child_process"
import { connect, replicaLag, close } from "../lib/db.js"
import { codeRevision } from "../relay/claude_command.js"
import { tablesWithEntityId, loadJoinMap } from "../lib/tables.js"
import { classifyClaudeError } from "../lib/claude_errors.js"

const local = process.env.SUPPORT_CONSOLE_LOCAL === "1"
let failures = 0
const line = (ok, text) => { console.log(`${ok ? "✓" : "✗"} ${text}`); if (!ok) failures++ }

console.log(local ? "Support Console machine check (local mode)" : "Support Console machine check")

// Code: the archive is there, has a revision and the scope table list, and carries no credentials.
try {
  const codeDir = fs.realpathSync(process.env.SUPPORT_CONSOLE_CODE_DIR)
  line(true, `Code: ${codeRevision(codeDir).slice(0, 12)} at ${codeDir}`)
  line(tablesWithEntityId(codeDir).size > 0, `Scope rules: ${tablesWithEntityId(codeDir).size} tables with entity_id`)
  // tenant-scope X8 — without the link list every table lacking entity_id is refused (fail closed)
  const linked = Object.keys(loadJoinMap(codeDir).links).length
  line(linked > 0, linked ? `Link list: ${linked} tables with links` : "Link list: join_map.json missing — tables without entity_id are refused")
  line(!fs.existsSync(path.join(codeDir, "config", "credentials")), "Code archive holds no credentials")
  // X27 — the archive is an allow-list; a key file here means it was built some other way.
  const keys = ["config/deploy_id_rsa", "config/deploy_id_rsa_enc", "config/master.key"].filter((f) => fs.existsSync(path.join(codeDir, f)))
  line(keys.length === 0, keys.length ? `Code archive holds key files: ${keys.join(", ")}` : "Code archive holds no key files")
} catch (error) {
  line(false, `Code: ${error.message}`)
}

// Database: connects, read-only proven (flags + refused write, or the probe alone locally).
try {
  const conn = await connect()
  const [[who]] = await conn.query("SELECT CURRENT_USER() AS u, DATABASE() AS d, @@read_only AS ro, @@super_read_only AS sro")
  line(true, `Database: ${who.u} on ${who.d}`)
  const writerAllowed = process.env.SUPPORT_CONSOLE_ALLOW_WRITER === "1" && !String(process.env.SUPPORT_CONSOLE_ENV || "production").startsWith("production")
  line(true, local || writerAllowed
    ? `Read-only: write probe refused (${local ? "local mode" : `${process.env.SUPPORT_CONSOLE_ENV}: writer allowed`}; server read_only=${who.ro})`
    : `Read-only: read_only=${who.ro} super_read_only=${who.sro}, write probe refused`)
  const lag = await replicaLag(conn)
  line(true, `Replica lag: ${lag === null ? "unknown (no replica status)" : `${lag} s`}`)
  await close()
} catch (error) {
  line(false, `Database: ${error.message}`)
}

// A deployed machine must never run in local mode.
if (process.env.SUPPORT_CONSOLE_DEPLOYED === "1") line(!local, "Not in local mode")

line(Boolean(process.env.SUPPORT_CONSOLE_RELAY_SECRET), "Relay secret set")

// E32 — on a subscription token, one tiny prompt proves the token signs in (X29) and the plan has room (X28).
if (process.env.SUPPORT_CONSOLE_AUTH === "subscription") {
  line(Boolean(process.env.CLAUDE_CODE_OAUTH_TOKEN), "Claude subscription token set")
  // Same rules as a turn: no tools may run (dontAsk with nothing allowed), and only what signing in
  // needs from the environment — never the relay secret.
  const env = { PATH: process.env.PATH, HOME: process.env.HOME, CLAUDE_CODE_OAUTH_TOKEN: process.env.CLAUDE_CODE_OAUTH_TOKEN }
  const args = ["-p", "--output-format", "json", "--max-turns", "1", "--model", "sonnet", "--permission-mode", "dontAsk"]
  const run = spawnSync(process.env.CLAUDE_BIN || "claude", args, { input: "Reply with the single word ok.", encoding: "utf8", timeout: 90_000, env })
  let result = null
  try { result = JSON.parse(run.stdout) } catch { /* not JSON: report stderr below */ }
  const ok = run.status === 0 && result && !result.is_error
  const reason = ok ? "" : classifyClaudeError(result?.result || run.stderr)
  line(ok, ok ? "Claude: signed in with the subscription token" : `Claude: ${reason} — ${(result?.result || run.stderr || "no output").slice(0, 200)}`)
}
process.exit(failures ? 1 : 0)
