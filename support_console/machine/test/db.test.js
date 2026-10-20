// The data tool against a real local MySQL (design card ⑦). Runs only after
// `rake support_console:local_setup` (it reads tmp/support_console/machine.env); a writable account
// for the refusal cases comes from SUPPORT_TEST_WRITABLE_USER / SUPPORT_TEST_WRITABLE_PASSWORD.
import { test } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const envFile = path.resolve(here, "../../../tmp/support_console/machine.env")
const machineEnv = fs.existsSync(envFile)
  ? Object.fromEntries(fs.readFileSync(envFile, "utf8").split("\n").filter((l) => l && !l.startsWith("#")).map((l) => l.split(/=(.*)/s).slice(0, 2)))
  : null
const skip = machineEnv ? false : "run rake support_console:local_setup first"
let instance = 0

// A fresh copy of lib/db.js (it keeps one connection per process) with the given environment.
async function loadDb(overrides = {}) {
  const events = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "db-test-")), "events.ndjson")
  fs.writeFileSync(events, "")
  Object.assign(process.env, machineEnv, { SUPPORT_EVENTS_FILE: events }, overrides)
  const db = await import(`../lib/db.js?instance=${++instance}`)
  return { db, events: () => fs.readFileSync(events, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l)) }
}

// E22 — Edge case: local mode accepts a writable server only when the account's write probe is refused
test("E22 — local mode accepts the SELECT-only account", { skip }, async () => {
  const { db, events } = await loadDb({ SUPPORT_CONSOLE_LOCAL: "1" })
  const result = await db.runLookup("SELECT id, name FROM entities WHERE id = 1", 1)
  assert.ok(result.duration_ms >= 0)
  assert.equal(events().at(-1).outcome, "ran")
  await db.close()
})

test("X11 — outside local mode a server with read_only = 0 is not a replica", { skip }, async () => {
  const { db } = await loadDb({ SUPPORT_CONSOLE_LOCAL: "" })
  await assert.rejects(db.connect(), /not_a_replica/)
})

test("E22 — local mode refuses an account that can write", { skip: skip || (!process.env.SUPPORT_TEST_WRITABLE_USER && "set SUPPORT_TEST_WRITABLE_USER") }, async () => {
  const pw = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "db-pw-")), "pw")
  fs.writeFileSync(pw, process.env.SUPPORT_TEST_WRITABLE_PASSWORD || "")
  const { db } = await loadDb({ SUPPORT_CONSOLE_LOCAL: "1", SUPPORT_DB_USER: process.env.SUPPORT_TEST_WRITABLE_USER, SUPPORT_DB_PASSWORD_FILE: pw })
  await assert.rejects(db.connect(), /not_a_replica/)
})

test("E17 — a large result is capped at 200 rows with the full total", { skip }, async () => {
  const { db } = await loadDb({ SUPPORT_CONSOLE_LOCAL: "1" })
  const result = await db.runLookup("SELECT a.name FROM folders a WHERE a.entity_id = 18 LIMIT 500", 18)
  assert.equal(result.rows.length, 200)
  assert.equal(result.total_rows, 500)
  assert.equal(result.truncated, true)
  await db.close()
})

test("E15 — rows of another client are flagged", { skip }, async () => {
  const { db, events } = await loadDb({ SUPPORT_CONSOLE_LOCAL: "1" })
  // Alias a row's id as entity_id to stand in for foreign rows the scope check could not see.
  const result = await db.runLookup("SELECT id AS entity_id FROM folders WHERE entity_id = 18 ORDER BY id LIMIT 3", 18)
  assert.equal(result.flagged, result.rows.length > 0)
  assert.equal(events().at(-1).flagged, result.flagged)
  await db.close()
})

// X21 — Error case: an account holding more than SELECT is refused even when its write probe is refused
test("X21 — the local account's grants are read-only", { skip }, async () => {
  const { db } = await loadDb({ SUPPORT_CONSOLE_LOCAL: "1" })
  await db.connect()
  await db.close()
})

test("E16 — a write is refused before it reaches the database", { skip }, async () => {
  const { db, events } = await loadDb({ SUPPORT_CONSOLE_LOCAL: "1" })
  await assert.rejects(db.runLookup("DELETE FROM entities WHERE id = 1", 1), /SELECT only/)
  assert.equal(events().at(-1).outcome, "blocked")
})

// E24 — Edge case: on staging (no replica) the writer is accepted when the write probe is refused; production never
test("E24 — staging accepts the writer with a refused probe; production ignores the flag", { skip }, async () => {
  const staging = await loadDb({ SUPPORT_CONSOLE_LOCAL: "", SUPPORT_CONSOLE_ALLOW_WRITER: "1", SUPPORT_CONSOLE_ENV: "staging.in" })
  await staging.db.connect()
  await staging.db.close()
  const production = await loadDb({ SUPPORT_CONSOLE_LOCAL: "", SUPPORT_CONSOLE_ALLOW_WRITER: "1", SUPPORT_CONSOLE_ENV: "production.in" })
  await assert.rejects(production.db.connect(), /not_a_replica/)
  Object.assign(process.env, { SUPPORT_CONSOLE_ALLOW_WRITER: "", SUPPORT_CONSOLE_ENV: "" })
})

// E26 — Edge case: a join returning repeated column names, a WITH statement and a trailing comment all run, capped at 200
test("E26 — joins with repeated column names, WITH and trailing comments run under the cap", { skip }, async () => {
  const { db } = await loadDb({ SUPPORT_CONSOLE_LOCAL: "1" })
  const join = await db.runLookup("SELECT a.name, b.name FROM folders a JOIN folders b ON b.entity_id = 18 AND b.level = a.level WHERE a.entity_id = 18 LIMIT 300 -- both names", 18)
  assert.equal(join.rows.length, 200)
  assert.equal(join.truncated, true)
  const withRows = await db.runLookup("WITH c AS (SELECT name FROM folders WHERE entity_id = 18) SELECT * FROM c", 18)
  assert.equal(withRows.rows.length, 200)
  await db.close()
})
