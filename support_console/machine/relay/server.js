#!/usr/bin/env node
// The relay: the support machine's only inbound service (design card ④). Rails posts a signed turn;
// the relay runs one headless Claude Code process for it and streams NDJSON events back:
//   progress — what Claude is doing (from stream-json tool_use blocks)
//   query    — one per lookup (from the turn's events file, numbered here)
//   text     — the final answer
//   session  — claude_session_id, as soon as Claude Code starts (so a stopped turn's transcript is known)
//   result   — claude_session_id, code_rev, lag_seconds, cost_usd, usage (input/output/cache_read/cache_write tokens)
//   error    — the machine could not answer (not_a_replica, db_unavailable, usage_limit, auth_failed, claude_failed)
import http from "node:http"
import crypto from "node:crypto"
import fs from "node:fs"
import path from "node:path"
import { spawn } from "node:child_process"
import { buildClaudeRun, codeRevision, transcriptPath } from "./claude_command.js"
import { classifyClaudeError } from "../lib/claude_errors.js"

const SECRET = process.env.SUPPORT_CONSOLE_RELAY_SECRET
const HOST = process.env.RELAY_HOST || "127.0.0.1"
const PORT = Number(process.env.RELAY_PORT || 4900)
const MAX_SKEW_SECONDS = 60
const MAX_BODY_BYTES = 64 * 1024
const KILL_GRACE_MS = 5_000
const TAIL_INTERVAL_MS = 250
const HEARTBEAT_MS = Number(process.env.RELAY_HEARTBEAT_MS || 30_000)

// One running Claude process per conversation (E11).
const running = new Map()

// X6, X8 — signature over "<ts>.<METHOD>.<path>.<body>", and a timestamp within 60 s.
export function verifySignature({ method, path: urlPath, body, timestamp, signature }, secret = SECRET, now = Date.now()) {
  if (!secret || !timestamp || !signature) return false
  if (Math.abs(now / 1000 - Number(timestamp)) > MAX_SKEW_SECONDS) return false
  const expected = crypto.createHmac("sha256", secret).update(`${timestamp}.${method}.${urlPath}.${body}`).digest("hex")
  const a = Buffer.from(expected)
  const b = Buffer.from(String(signature))
  return a.length === b.length && crypto.timingSafeEqual(a, b)
}

// H10 — Claude Code's token counts for the turn, in the names Rails sums per conversation; null when absent.
export function tokenUsage(usage) {
  if (!usage) return null
  return {
    input: usage.input_tokens ?? 0,
    output: usage.output_tokens ?? 0,
    cache_read: usage.cache_read_input_tokens ?? 0,
    cache_write: usage.cache_creation_input_tokens ?? 0
  }
}

// Plain-words progress for a tool call, so the support user sees what Claude is doing.
export function describeToolUse(block, codeDir) {
  const input = block.input || {}
  const rel = (p) => (p && codeDir && p.startsWith(codeDir) ? path.relative(codeDir, p) : p)
  switch (block.name) {
    case "Read": return `Reading ${rel(input.file_path)}`
    case "Grep": return `Searching the code for “${input.pattern}”`
    case "Glob": return `Listing files ${input.pattern || ""}`.trim()
    case "mcp__db__query": return "Looking up data"
    case "mcp__db__describe_tables": return `Checking columns of ${(input.names || []).join(", ")}`
    default: return `Using ${block.name}`
  }
}

function send(res, event) {
  res.write(JSON.stringify(event) + "\n")
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0
    const chunks = []
    req.on("data", (chunk) => {
      size += chunk.length
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error("body too large"), { status: 413 }))
        req.destroy()
      } else chunks.push(chunk)
    })
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")))
    req.on("error", reject)
  })
}

// Runs one turn and streams its events to the response.
async function postTurn(turn, res) {
  const key = String(turn.session_key)
  if (running.has(key)) {
    res.writeHead(409).end()
    return
  }

  const run = buildClaudeRun({
    entityId: Number(turn.entity_id),
    turnId: `${Date.now()}-${crypto.randomBytes(4).toString("hex")}`,
    question: String(turn.question || ""),
    resumeId: turn.resume_id || null,
    brief: String(turn.brief || ""),
    model: String(turn.model || ""),
  })
  res.writeHead(200, { "Content-Type": "application/x-ndjson" })

  const child = spawn(run.bin, run.args, { cwd: run.cwd, env: run.env, stdio: ["pipe", "pipe", "pipe"] })
  running.set(key, child)
  // A claude that cannot start (missing binary, EAGAIN, ENOMEM) fails this turn, not the relay.
  let spawnError = null
  child.on("error", (error) => { spawnError = error })
  child.stdin.on("error", () => {})
  child.stdin.end(run.stdin)
  // Rails gives up on a stream silent for 120 s; Claude can write a long answer for longer than that
  // after its last tool call, so say it is still working.
  const heartbeat = setInterval(() => send(res, { type: "ping" }), HEARTBEAT_MS)

  let seq = 0
  let offset = 0
  let lastLag = null
  let result = null
  let failed = null
  let stderr = ""

  // Forward lookups written by the hook and the db MCP server, numbered in the order they happened.
  const tail = () => {
    let data
    try {
      const fd = fs.openSync(run.eventsFile, "r")
      const size = fs.fstatSync(fd).size
      if (size <= offset) { fs.closeSync(fd); return }
      const buffer = Buffer.alloc(size - offset)
      fs.readSync(fd, buffer, 0, buffer.length, offset)
      fs.closeSync(fd)
      data = buffer.toString("utf8")
    } catch { return }
    const end = data.lastIndexOf("\n")
    if (end < 0) return
    offset += Buffer.byteLength(data.slice(0, end + 1))
    for (const line of data.slice(0, end).split("\n")) {
      if (!line.trim()) continue
      // A torn or garbled line must not throw inside setInterval: that would crash the relay and every
      // turn in flight. Skip it; the query record simply misses that one lookup.
      let event
      try { event = JSON.parse(line) } catch { console.error(`[relay] unreadable events line skipped`); continue }
      if (event.type === "error") {
        // X11, X12 — the turn cannot be answered; stop Claude and say why.
        failed = failed || { type: "error", code: event.code, message: event.message }
        child.kill("SIGTERM")
      } else {
        if (event.lag_seconds !== undefined && event.lag_seconds !== null) lastLag = event.lag_seconds
        send(res, { ...event, seq: ++seq, code_rev: run.codeRev })
      }
    }
  }
  const timer = setInterval(tail, TAIL_INTERVAL_MS)

  // Claude Code's stream-json: one JSON object per line on stdout.
  let pending = ""
  child.stdout.on("data", (chunk) => {
    pending += chunk.toString("utf8")
    let newline
    while ((newline = pending.indexOf("\n")) >= 0) {
      const line = pending.slice(0, newline)
      pending = pending.slice(newline + 1)
      if (!line.trim()) continue
      let message
      try { message = JSON.parse(line) } catch { continue }
      if (message.type === "system" && message.subtype === "init" && message.session_id) {
        // X25 — Rails records the id now, so retention can delete the transcript of a turn that is
        // later stopped, times out or fails (none of which reach the result below).
        send(res, { type: "session", claude_session_id: message.session_id })
      } else if (message.type === "assistant") {
        for (const block of message.message?.content || []) {
          if (block.type === "tool_use") send(res, { type: "progress", text: describeToolUse(block, run.codeDir) })
        }
      } else if (message.type === "result") {
        result = message
      }
    }
  })
  child.stderr.on("data", (chunk) => { stderr = (stderr + chunk.toString("utf8")).slice(-4000) })

  // Rails went away (its own timeout): stop Claude rather than finish for nobody.
  res.on("close", () => { if (running.get(key) === child) child.kill("SIGTERM") })

  await new Promise((resolve) => {
    child.on("close", resolve)
    child.on("error", resolve)
  })
  clearInterval(timer)
  clearInterval(heartbeat)
  tail()
  running.delete(key)

  if (spawnError) {
    send(res, { type: "error", code: "claude_failed", message: `could not start claude: ${spawnError.message}` })
  } else if (failed) {
    send(res, failed)
  } else if (result && !result.is_error) {
    // The final answer, then the turn's result.
    send(res, { type: "text", delta: String(result.result || "") })
    send(res, { type: "result", claude_session_id: result.session_id, code_rev: run.codeRev, lag_seconds: lastLag, cost_usd: result.total_cost_usd ?? null, usage: tokenUsage(result.usage) })
  } else if (child.signalCode) {
    // E9 — stopped on request: no result; Rails already closed the turn.
  } else {
    // X28, X29 — a reached usage limit or a dead token gets its own code, so Rails can say which.
    const message = (result?.result || stderr || "Claude Code exited without a result").slice(0, 500)
    send(res, { type: "error", code: classifyClaudeError(message), message })
  }
  res.end()
}

function stopTurn(sessionKey, res) {
  const child = running.get(String(sessionKey))
  if (!child) return res.writeHead(404).end()
  // E9 — SIGTERM, then SIGKILL if Claude does not exit in time.
  child.kill("SIGTERM")
  setTimeout(() => { if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL") }, KILL_GRACE_MS).unref()
  res.writeHead(204).end()
}

function deleteTranscript({ entity_id: entityId, claude_session_id: claudeId }, res) {
  // Only ids Claude Code generates; nothing that could walk out of the projects folder.
  if (!/^\d+$/.test(String(entityId)) || !/^[0-9a-f-]{8,64}$/i.test(String(claudeId))) return res.writeHead(400).end()
  const file = transcriptPath(process.env.SUPPORT_CONSOLE_CLIENTS_DIR, entityId, claudeId)
  if (!fs.existsSync(file)) return res.writeHead(404).end()
  fs.unlinkSync(file)
  res.writeHead(204).end()
}

export function createServer() {
  return http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://relay")
    try {
      // Unsigned health check for local_check / machine_check: no client data, no secrets.
      if (req.method === "GET" && url.pathname === "/health") {
        res.writeHead(200, { "Content-Type": "application/json" })
        return res.end(JSON.stringify({ ok: true, local: process.env.SUPPORT_CONSOLE_LOCAL === "1", code_rev: codeRevision(fs.realpathSync(process.env.SUPPORT_CONSOLE_CODE_DIR)) }))
      }

      const body = await readBody(req)
      const signed = verifySignature({ method: req.method, path: url.pathname, body, timestamp: req.headers["x-timestamp"], signature: req.headers["x-signature"] })
      if (!signed) return res.writeHead(401).end()
      const payload = body ? JSON.parse(body) : {}

      if (req.method === "POST" && url.pathname === "/turns") return await postTurn(payload, res)
      if (req.method === "DELETE" && url.pathname === "/turns/current") return stopTurn(payload.session_key, res)
      if (req.method === "DELETE" && url.pathname === "/transcripts") return deleteTranscript(payload, res)
      res.writeHead(404).end()
    } catch (error) {
      if (!res.headersSent) res.writeHead(error.status || 500).end()
      else res.end()
      console.error(`[relay] ${req.method} ${url.pathname}: ${error.message}`)
    }
  })
}

// Started directly (not imported by the tests)? Compare real paths: systemd starts the relay through
// the /opt/support-console/current symlink, while import.meta.url is the resolved directory.
const startedDirectly = (() => {
  try {
    return fs.realpathSync(process.argv[1]) === fs.realpathSync(new URL(import.meta.url).pathname)
  } catch {
    return false
  }
})()
if (startedDirectly) {
  if (!SECRET) {
    console.error("SUPPORT_CONSOLE_RELAY_SECRET is not set")
    process.exit(1)
  }
  const server = createServer()
  server.on("error", (error) => {
    // A second relay (or anything else) on the port: say so plainly instead of a stack trace.
    if (error.code === "EADDRINUSE") {
      console.error(`[relay] ${HOST}:${PORT} is already in use — another relay is probably running (find it with: ss -ltnp | grep ${PORT})`)
      process.exit(1)
    }
    throw error
  })
  server.listen(PORT, HOST, () => console.log(`[relay] listening on ${HOST}:${PORT}${process.env.SUPPORT_CONSOLE_LOCAL === "1" ? " (local mode)" : ""}`))
}
