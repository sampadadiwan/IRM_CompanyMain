// The only path to client data (design card ⑦): one read-only connection to the replica as
// support_ro, with the replica proven at connect time, a 30 s statement limit and a row cap.
import fs from "node:fs"
import mysql from "mysql2/promise"
import { prepareStatement, heldBack, withoutScope } from "./sql_rules.js"
import { appendEvent } from "./events.js"
import { tablesWithEntityId, loadJoinMap } from "./tables.js"

export const ROW_CAP = 200
const STATEMENT_TIMEOUT_MS = 30_000
const LOCAL = process.env.SUPPORT_CONSOLE_LOCAL === "1"
// E24 — staging has no read replica: there the writer is accepted under the same rule as local mode.
// Production never: the flag is ignored for any environment whose name starts with "production".
const ALLOW_WRITER =
  process.env.SUPPORT_CONSOLE_ALLOW_WRITER === "1" && !String(process.env.SUPPORT_CONSOLE_ENV || "production").startsWith("production")

// X21 — the only privileges support_ro may hold. USAGE is "no privilege"; REPLICATION CLIENT reads lag.
const ALLOWED_PRIVILEGES = new Set(["USAGE", "SELECT", "SHOW VIEW", "REPLICATION CLIENT"])

let connection
let replicaError

function password() {
  // The password lives in a file only the relay's user can read, never in the environment.
  const file = process.env.SUPPORT_DB_PASSWORD_FILE
  return file ? fs.readFileSync(file, "utf8").trim() : ""
}

// Opens the connection once per process (one process per turn) and proves it is read-only.
//
// @returns the connection
// @throws Error("not_a_replica") or Error("db_unavailable")
export async function connect() {
  if (connection) return connection
  if (replicaError) throw replicaError

  try {
    connection = await mysql.createConnection({
      host: process.env.SUPPORT_DB_HOST,
      port: Number(process.env.SUPPORT_DB_PORT || 3306),
      user: process.env.SUPPORT_DB_USER,
      password: password(),
      database: process.env.SUPPORT_DB_NAME,
      connectTimeout: 5_000,
    })
  } catch (error) {
    // X12 — the replica cannot be reached.
    replicaError = Object.assign(new Error(`db_unavailable: ${error.message}`), { code: "db_unavailable" })
    throw replicaError
  }

  await connection.query(`SET SESSION max_execution_time = ${STATEMENT_TIMEOUT_MS}`)
  // E17, E26 — the row cap is the server's, so it applies to joins with repeated column names and to
  // WITH statements alike, and the statement runs exactly as written (no wrapper to break).
  await connection.query(`SET SESSION sql_select_limit = ${ROW_CAP + 1}`)

  // X11 — a deployed machine must be on a replica: both read-only flags on.
  const [[flags]] = await connection.query("SELECT @@read_only AS ro, @@super_read_only AS sro")
  const flagsOk = Number(flags.ro) === 1 && Number(flags.sro) === 1

  // A write the server refuses proves the account cannot write, whatever the flags say.
  let probeRefused = false
  try {
    await connection.query("CREATE TEMPORARY TABLE support_console_probe (x INT)")
    await connection.query("DROP TEMPORARY TABLE support_console_probe")
  } catch {
    probeRefused = true
  }

  // X21 — the refused probe only shows the account lacks CREATE TEMPORARY TABLES; the grants show it
  // holds nothing that writes, reads files or sees other sessions, which matters most on staging's writer.
  const grantsOk = onlyReadGrants(await connection.query("SHOW GRANTS").then(([rows]) => rows.flatMap(Object.values)))

  // E22 — local mode, E24 — staging's writer: not a replica, so only the refused probe is required.
  const ok = grantsOk && (LOCAL || ALLOW_WRITER ? probeRefused : flagsOk && probeRefused)
  if (!ok) {
    await connection.end()
    connection = undefined
    // Same code either way, so Rails shows the same "unavailable" message; the text says which check failed.
    const why = grantsOk ? "not_a_replica" : "not_a_replica: support_ro holds more than SELECT"
    replicaError = Object.assign(new Error(why), { code: "not_a_replica" })
    throw replicaError
  }
  return connection
}

// @param grants the lines of SHOW GRANTS, e.g. "GRANT SELECT, SHOW VIEW ON `IRM`.* TO `support_ro`@`10.0.3.9`"
// @returns true when every line grants only ALLOWED_PRIVILEGES. A role grant ("GRANT `r`@`%` TO …") or
//          any line that does not read as GRANT <privileges> ON … is refused, since its rights are unknown.
export function onlyReadGrants(grants) {
  return grants.every((line) => {
    const match = /^GRANT (.+?) ON /i.exec(String(line))
    if (!match) return false
    // Column grants read "SELECT (col1, col2)"; the parenthesised list is not a privilege.
    return match[1].replace(/\([^)]*\)/g, "").split(",").every((p) => ALLOWED_PRIVILEGES.has(p.trim().toUpperCase()))
  })
}

// @returns seconds the replica is behind, or null when unknown (no REPLICATION CLIENT, or not a replica)
export async function replicaLag(conn) {
  try {
    const [rows] = await conn.query("SHOW REPLICA STATUS")
    const lag = rows[0]?.Seconds_Behind_Source
    return lag === undefined || lag === null ? null : Number(lag)
  } catch {
    return null
  }
}

// Runs one lookup for the conversation's client and records it.
//
// @returns {{columns, rows, total_rows, truncated, lag_seconds, duration_ms}}
// @throws Error with a reason the caller shows to Claude
export async function runLookup(sql, entityId) {
  // The same rules as the hook: the hook may be bypassed by a misconfiguration, this may not.
  // X16 — what runs is the statement rebuilt from the checked parse, never the text as sent.
  const prepared = prepareStatement(sql, entityId, tablesWithEntityId(), process.env.SUPPORT_DB_NAME, loadJoinMap())
  if (prepared.reason) {
    appendEvent({ sql: sql || "(no statement)", outcome: "blocked", reason: prepared.reason })
    throw new Error(`Lookup refused (${prepared.reason}).`)
  }

  const conn = await connect()
  const lag = await replicaLag(conn)
  const started = Date.now()
  let rows
  let fields
  try {
    // E17 — sql_select_limit returns at most one more than the cap, so a cut result is known.
    ;[rows, fields] = await conn.query({ sql: prepared.sql, rowsAsArray: false })
  } catch (error) {
    // E19 — 3024 is MySQL's "maximum statement execution time exceeded".
    const timedOut = error.errno === 3024
    appendEvent({ sql, outcome: "failed", reason: timedOut ? "query timed out" : error.message.slice(0, 200), duration_ms: Date.now() - started, lag_seconds: lag })
    throw new Error(timedOut ? "query timed out (30 s); filter on an indexed column or aggregate" : `query failed: ${error.message}`)
  }

  const duration = Date.now() - started
  let total = rows.length
  const truncated = rows.length > ROW_CAP
  if (truncated) {
    // E17 — the full count, for the record and so Claude knows to aggregate. A statement that cannot be
    // counted as a derived table (E26: repeated column names) reports the total as unknown.
    try {
      const [[count]] = await conn.query(`SELECT COUNT(*) AS n FROM (${prepared.sql}) AS support_console_c`)
      total = Number(count.n)
    } catch {
      total = null
    }
    rows = rows.slice(0, ROW_CAP)
  }

  // tenant-scope ⑦ X11 — any row whose hidden scope column names another client: nothing goes back
  // to Claude, the lookup is recorded as blocked and flagged (super users get the bell alert).
  if (heldBack(rows, entityId)) {
    appendEvent({ sql, outcome: "blocked", reason: "rows from another client", flagged: true, row_count: total, duration_ms: duration, lag_seconds: lag })
    throw new Error("Lookup blocked: rows from another client.")
  }
  // H1 — Claude sees exactly the columns it asked for
  const visible = withoutScope(rows, (fields || []).map((f) => f.name))
  appendEvent({ sql, outcome: "ran", row_count: total, duration_ms: duration, lag_seconds: lag, flagged: false })
  return { columns: visible.columns, rows: visible.rows, total_rows: total, truncated, lag_seconds: lag, duration_ms: duration }
}

// @returns column descriptions for the named tables
export async function describeTables(names) {
  const conn = await connect()
  const [rows] = await conn.query(
    "SELECT table_name AS table_name, column_name AS column_name, column_type AS column_type, is_nullable AS is_nullable " +
      "FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name IN (?) ORDER BY table_name, ordinal_position",
    [names]
  )
  return rows
}

export async function close() {
  if (connection) await connection.end()
  connection = undefined
}
