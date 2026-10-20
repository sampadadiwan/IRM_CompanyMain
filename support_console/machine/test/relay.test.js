// The relay against a fake `claude` (design card ④): signatures, one turn per conversation,
// stream translation, stop and machine-side errors.
import { test, before, after } from "node:test"
import assert from "node:assert/strict"
import crypto from "node:crypto"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "relay-test-"))
const SECRET = "relay-test-secret"

process.env.SUPPORT_CONSOLE_RELAY_SECRET = SECRET
process.env.SUPPORT_CONSOLE_CLIENTS_DIR = path.join(tmp, "clients")
fs.mkdirSync(path.join(tmp, "code-abc"), { recursive: true })
fs.writeFileSync(path.join(tmp, "code-abc", "REVISION"), "abc1234\n")
fs.symlinkSync(path.join(tmp, "code-abc"), path.join(tmp, "current"))
process.env.SUPPORT_CONSOLE_CODE_DIR = path.join(tmp, "current")
process.env.CLAUDE_BIN = path.join(here, "fake_claude.js")
fs.chmodSync(process.env.CLAUDE_BIN, 0o755)

const { createServer, verifySignature } = await import("../relay/server.js")
let server
let base

before(async () => {
  server = createServer()
  await new Promise((r) => server.listen(0, "127.0.0.1", r))
  base = `http://127.0.0.1:${server.address().port}`
})
after(() => server.close())

function signed(method, urlPath, payload, { ts = Math.floor(Date.now() / 1000), secret = SECRET } = {}) {
  const body = JSON.stringify(payload)
  const signature = crypto.createHmac("sha256", secret).update(`${ts}.${method}.${urlPath}.${body}`).digest("hex")
  return fetch(base + urlPath, { method, body, headers: { "Content-Type": "application/json", "X-Timestamp": String(ts), "X-Signature": signature } })
}

const turn = (key, extra = {}) => ({ session_key: key, entity_id: 18, question: "Why zero?", resume_id: null, brief: "client 18", ...extra })
const events = async (res) => (await res.text()).trim().split("\n").filter(Boolean).map((l) => JSON.parse(l))

test("H1 — a turn streams progress, the lookup, the answer and the result", async () => {
  const res = await signed("POST", "/turns", turn("18:1"))
  assert.equal(res.status, 200)
  const list = await events(res)
  assert.ok(list.some((e) => e.type === "progress" && e.text.includes("closing_balance")))
  const query = list.find((e) => e.type === "query")
  assert.equal(query.seq, 1)
  assert.equal(query.code_rev, "abc1234")
  assert.equal(list.find((e) => e.type === "text").delta, "Answer to: Why zero?")
  const result = list.find((e) => e.type === "result")
  assert.equal(result.claude_session_id, "11111111-2222-3333-4444-555555555555")
  assert.equal(result.lag_seconds, 4)
})

test("H3 — a follow-up passes --resume and the tools are locked down", async () => {
  const argsFile = path.join(tmp, "args.json")
  process.env.FAKE_CLAUDE_ARGS_FILE = argsFile
  await events(await signed("POST", "/turns", turn("18:2", { resume_id: "aaaaaaaa-bbbb" })))
  delete process.env.FAKE_CLAUDE_ARGS_FILE
  const args = JSON.parse(fs.readFileSync(argsFile, "utf8"))
  assert.deepEqual(args.slice(args.indexOf("--resume"), args.indexOf("--resume") + 2), ["--resume", "aaaaaaaa-bbbb"])
  // X9 — no Bash: restricted mode, only the read tools.
  assert.ok(args.includes("--restricted"))
  assert.deepEqual(args.slice(args.indexOf("--tools") + 1, args.indexOf("--tools") + 4), ["Read", "Grep", "Glob"])
})

// X6 — Error case: a bad signature is refused and no turn starts
test("X6 — wrong signature is refused", async () => {
  const res = await signed("POST", "/turns", turn("18:3"), { secret: "wrong" })
  assert.equal(res.status, 401)
})

// X8 — Error case: a timestamp more than 60 s old is refused
test("X8 — stale timestamp is refused", async () => {
  const res = await signed("POST", "/turns", turn("18:4"), { ts: Math.floor(Date.now() / 1000) - 61 })
  assert.equal(res.status, 401)
  assert.equal(verifySignature({ method: "POST", path: "/turns", body: "{}", timestamp: "1", signature: "x" }, SECRET), false)
})

// X22 — Error case: Claude never inherits the relay secret, and its read tools cannot reach the machine's secrets or other clients
test("X22 — Claude gets no relay secret and the read tools are denied the secret paths", async () => {
  const argsFile = path.join(tmp, "args-x22.json")
  const envFile = path.join(tmp, "env-x22.json")
  Object.assign(process.env, { FAKE_CLAUDE_ARGS_FILE: argsFile, FAKE_CLAUDE_ENV_FILE: envFile, SUPPORT_DB_PASSWORD_FILE: "/etc/support-console/db_password" })
  await events(await signed("POST", "/turns", turn("18:20")))
  for (const name of ["FAKE_CLAUDE_ARGS_FILE", "FAKE_CLAUDE_ENV_FILE", "SUPPORT_DB_PASSWORD_FILE"]) delete process.env[name]

  const env = JSON.parse(fs.readFileSync(envFile, "utf8"))
  assert.equal(env.SUPPORT_CONSOLE_RELAY_SECRET, undefined)
  assert.equal(env.SUPPORT_DB_PASSWORD_FILE, undefined)
  assert.equal(env.SUPPORT_ENTITY_ID, "18")
  // One Claude Code config folder per client, outside the clients folder.
  assert.match(env.CLAUDE_CONFIG_DIR, /claude-clients\/18$/)

  const args = JSON.parse(fs.readFileSync(argsFile, "utf8"))
  const settings = JSON.parse(fs.readFileSync(args[args.indexOf("--settings") + 1], "utf8"))
  for (const rule of ["Read(//etc/**)", "Read(//proc/**)", "Read(~/.claude/**)", `Read(/${path.join(tmp, "clients")}/**)`]) {
    assert.ok(settings.permissions.deny.includes(rule), `${rule} is not denied`)
  }
  assert.equal(args[args.indexOf("--max-turns") + 1], "40")
})

// X25 — Edge case: the Claude session id is sent as soon as Claude starts, so a stopped turn's transcript can still be deleted
test("X25 — the session id comes first, before any answer", async () => {
  process.env.FAKE_CLAUDE_MODE = "slow"
  const first = signed("POST", "/turns", turn("18:21"))
  await new Promise((r) => setTimeout(r, 500))
  await signed("DELETE", "/turns/current", { session_key: "18:21" })
  const list = await events(await first)
  delete process.env.FAKE_CLAUDE_MODE
  assert.deepEqual(list.find((e) => e.type === "session"), { type: "session", claude_session_id: "11111111-2222-3333-4444-555555555555" })
  assert.ok(!list.some((e) => e.type === "result"))
})

test("a torn events line is skipped, not fatal to the relay", async () => {
  process.env.FAKE_CLAUDE_MODE = "garbled"
  const list = await events(await signed("POST", "/turns", turn("18:22")))
  delete process.env.FAKE_CLAUDE_MODE
  assert.equal(list.at(-1).type, "result")
  assert.equal((await fetch(base + "/health")).status, 200)
})

// X28 — Error case: a subscription out of usage ends the turn with usage_limit, not a generic failure
test("X28 — a reached usage limit is reported as usage_limit", async () => {
  process.env.FAKE_CLAUDE_MODE = "usage_limit"
  const list = await events(await signed("POST", "/turns", turn("18:30")))
  delete process.env.FAKE_CLAUDE_MODE
  assert.equal(list.at(-1).code, "usage_limit")
})

// X29 — Error case: an expired or revoked subscription token ends the turn with auth_failed
test("X29 — a dead token is reported as auth_failed", async () => {
  process.env.FAKE_CLAUDE_MODE = "auth_expired"
  const list = await events(await signed("POST", "/turns", turn("18:31")))
  delete process.env.FAKE_CLAUDE_MODE
  assert.equal(list.at(-1).code, "auth_failed")
  const { classifyClaudeError } = await import("../lib/claude_errors.js")
  assert.equal(classifyClaudeError("Claude AI usage limit reached|1760000000"), "usage_limit")
  assert.equal(classifyClaudeError("Invalid API key · Please run /login"), "auth_failed")
  assert.equal(classifyClaudeError("boom"), "claude_failed")
})

// E32 — Edge case: on a subscription token the models are Claude Code's aliases and Bedrock is never switched on
test("E32 — subscription mode uses the aliases and no Bedrock", async () => {
  const { modelFor } = await import("../relay/claude_command.js")
  assert.equal(modelFor("opus", { SUPPORT_CONSOLE_AUTH: "subscription" }), "opus")
  assert.equal(modelFor("anything", { SUPPORT_CONSOLE_AUTH: "subscription" }), "sonnet")
  assert.equal(modelFor("opus", { SUPPORT_CONSOLE_AUTH: "bedrock" }), "global.anthropic.claude-opus-5-5")

  const envFile = path.join(tmp, "env-e32.json")
  Object.assign(process.env, { FAKE_CLAUDE_ENV_FILE: envFile, SUPPORT_CONSOLE_AUTH: "subscription", CLAUDE_CODE_OAUTH_TOKEN: "sk-ant-oat01-test" })
  await events(await signed("POST", "/turns", turn("18:32")))
  for (const name of ["FAKE_CLAUDE_ENV_FILE", "SUPPORT_CONSOLE_AUTH", "CLAUDE_CODE_OAUTH_TOKEN"]) delete process.env[name]
  const env = JSON.parse(fs.readFileSync(envFile, "utf8"))
  assert.equal(env.CLAUDE_CODE_OAUTH_TOKEN, "sk-ant-oat01-test")
  assert.equal(env.CLAUDE_CODE_USE_BEDROCK, undefined)
})

// E11 — Edge case: a second turn for a running conversation gets 409; Stop ends the first
test("E11 — one turn per conversation, and Stop ends it", async () => {
  process.env.FAKE_CLAUDE_MODE = "slow"
  const first = signed("POST", "/turns", turn("18:5"))
  await new Promise((r) => setTimeout(r, 500))
  const second = await signed("POST", "/turns", turn("18:5"))
  assert.equal(second.status, 409)
  const stop = await signed("DELETE", "/turns/current", { session_key: "18:5" })
  assert.equal(stop.status, 204)
  const list = await events(await first)
  delete process.env.FAKE_CLAUDE_MODE
  assert.ok(!list.some((e) => e.type === "result"))
  assert.equal((await signed("DELETE", "/turns/current", { session_key: "18:5" })).status, 404)
})

// X11 — Error case: the data tool reports not_a_replica; the turn ends with that error
test("X11 — a db error ends the turn", async () => {
  process.env.FAKE_CLAUDE_MODE = "db_error"
  const list = await events(await signed("POST", "/turns", turn("18:6")))
  delete process.env.FAKE_CLAUDE_MODE
  assert.deepEqual(list.at(-1), { type: "error", code: "not_a_replica", message: "not_a_replica" })
})

test("Claude failing reports claude_failed", async () => {
  process.env.FAKE_CLAUDE_MODE = "fail"
  const list = await events(await signed("POST", "/turns", turn("18:7")))
  delete process.env.FAKE_CLAUDE_MODE
  assert.equal(list.at(-1).code, "claude_failed")
})

test("transcript delete refuses ids that could leave the projects folder", async () => {
  assert.equal((await signed("DELETE", "/transcripts", { entity_id: 18, claude_session_id: "../../etc" })).status, 400)
  assert.equal((await signed("DELETE", "/transcripts", { entity_id: 18, claude_session_id: "11111111-2222" })).status, 404)
})

// E30 — Edge case: the relay maps "sonnet" / "opus" to the environment's ids and never accepts a raw id
test("E30 — model names map to ids; unknown or raw ids fall back to Sonnet", async () => {
  const { modelFor } = await import("../relay/claude_command.js")
  assert.equal(modelFor("opus", {}), "global.anthropic.claude-opus-5-5")
  assert.equal(modelFor("sonnet", {}), "global.anthropic.claude-sonnet-5-5")
  assert.equal(modelFor("anthropic.claude-fable-5-1", {}), "global.anthropic.claude-sonnet-5-5")
  assert.equal(modelFor("", {}), "global.anthropic.claude-sonnet-5-5")
  assert.equal(modelFor("opus", { SUPPORT_CONSOLE_LOCAL: "1" }), "opus")
  assert.equal(modelFor("opus", { SUPPORT_CONSOLE_MODEL_OPUS: "apac.anthropic.claude-opus-5-5" }), "apac.anthropic.claude-opus-5-5")

  const argsFile = path.join(tmp, "args-model.json")
  process.env.FAKE_CLAUDE_ARGS_FILE = argsFile
  await events(await signed("POST", "/turns", turn("18:8", { model: "opus" })))
  delete process.env.FAKE_CLAUDE_ARGS_FILE
  const args = JSON.parse(fs.readFileSync(argsFile, "utf8"))
  assert.equal(args[args.indexOf("--model") + 1], "global.anthropic.claude-opus-5-5")
})

// The machine bundle is built from git: every file the relay loads at start must be tracked.
// (claude/CLAUDE.md was once silently dropped by the repo's .gitignore and the relay could not start.)
test("the files the relay loads are tracked by git", async () => {
  const { execFileSync } = await import("node:child_process")
  const tracked = execFileSync("git", ["ls-files", "claude", "relay", "hooks", "db-mcp", "lib"], { cwd: path.join(here, ".."), encoding: "utf8" })
  for (const file of ["claude/support_brief.md", "relay/server.js", "relay/claude_command.js", "hooks/scope_guard.js", "db-mcp/server.js"]) {
    assert.ok(tracked.split("\n").includes(file), `${file} is not tracked by git`)
  }
})
