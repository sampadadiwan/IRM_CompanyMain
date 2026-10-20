// Builds one headless Claude Code run for a turn (design card ⑤): the per-turn settings and MCP
// config, the argument list and the environment. The question goes in on stdin, because a
// positional prompt after variadic flags like --tools would be read as another tool name.
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const MACHINE_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const BRIEF = fs.readFileSync(path.join(MACHINE_DIR, "claude", "support_brief.md"), "utf8")
const READ_TOOLS = ["Read", "Grep", "Glob"]

// E30 — the model a turn runs on, from the name Rails sends ("sonnet" | "opus"). Unknown names are
// Sonnet, and a raw model id is never accepted, so a request cannot choose anything else. Locally and
// on a subscription token (E32), Claude Code's own aliases; on Bedrock, the environment's Bedrock ids.
export function modelFor(name, config = process.env) {
  const choice = name === "opus" ? "opus" : "sonnet"
  const aliases = config.SUPPORT_CONSOLE_LOCAL === "1" || config.SUPPORT_CONSOLE_AUTH === "subscription"
  // Bedrock: global cross-region inference profiles (base ids are refused on demand).
  if (choice === "opus") return config.SUPPORT_CONSOLE_MODEL_OPUS || (aliases ? "opus" : "global.anthropic.claude-opus-5-5")
  return config.SUPPORT_CONSOLE_MODEL_SONNET || (aliases ? "sonnet" : "global.anthropic.claude-sonnet-5-5")
}
const DB_TOOLS = ["mcp__db__query", "mcp__db__describe_tables"]
// X22 — the only relay variables Claude (and the hook it starts) inherits. Never the relay secret or
// anything else in machine.env: a prompt planted in client data could ask Claude to quote them.
// FAKE_CLAUDE_* only steer the tests' stand-in claude.
const PASS_ENV = /^(PATH|HOME|USER|LANG|LC_[A-Z_]+|TZ|TMPDIR|AWS_REGION|AWS_DEFAULT_REGION|AWS_PROFILE|CLAUDE_CODE_[A-Z_]+|ANTHROPIC_[A-Z_]+|FAKE_CLAUDE_[A-Z_]+)$/
// A runaway turn stops after this many model turns instead of looping until someone presses Stop.
const DEFAULT_MAX_TURNS = 40

// @param turn {entityId, turnId, question, resumeId, brief}
// @returns {{bin, args, env, cwd, codeDir, codeRev, eventsFile, stdin}}
export function buildClaudeRun(turn, config = process.env) {
  const clientsDir = config.SUPPORT_CONSOLE_CLIENTS_DIR
  // E12 — resolve the code symlink once, so a deploy mid-turn does not change what this turn reads.
  const codeDir = fs.realpathSync(config.SUPPORT_CONSOLE_CODE_DIR)
  const cwd = path.join(clientsDir, String(turn.entityId))
  const turnDir = path.join(cwd, ".turns", turn.turnId)
  fs.mkdirSync(turnDir, { recursive: true })
  const eventsFile = path.join(turnDir, "events.ndjson")
  fs.writeFileSync(eventsFile, "")

  // Permissions and the scope hook (card ⑥). With --restricted these are the only settings used.
  // X22 — deny wins over allow, so the read tools reach the code but none of the machine's secrets,
  // other clients' folders or saved conversations, whatever --restricted does. Claude needs nothing
  // under the clients folder: --resume reads the transcript itself, not through the Read tool.
  const configDir = claudeConfigDir(turn.entityId, config)
  const secretDirs = [config.SUPPORT_DB_PASSWORD_FILE && path.dirname(config.SUPPORT_DB_PASSWORD_FILE), clientsDir, configRoot(config)]
  const settings = {
    permissions: {
      allow: [...READ_TOOLS, ...DB_TOOLS],
      deny: [
        "Bash", "Write", "Edit", "NotebookEdit", "WebFetch", "WebSearch",
        "Read(//etc/**)", "Read(//proc/**)", "Read(//sys/**)", "Read(//root/**)", "Read(//var/**)",
        "Read(~/.claude/**)", "Read(~/.aws/**)", "Read(~/.ssh/**)", "Read(~/.config/**)",
        ...[...new Set(secretDirs.filter(Boolean))].map((dir) => `Read(/${path.resolve(dir)}/**)`),
      ],
    },
    hooks: {
      PreToolUse: [
        { matcher: "mcp__db__query", hooks: [{ type: "command", command: `node ${path.join(MACHINE_DIR, "hooks", "scope_guard.js")}` }] },
      ],
    },
  }
  const settingsFile = path.join(turnDir, "settings.json")
  fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2))

  // The only MCP server: the read-only data tool (card ⑦). No password here — only its file's path.
  const dbEnv = {
    SUPPORT_ENTITY_ID: String(turn.entityId),
    SUPPORT_EVENTS_FILE: eventsFile,
    SUPPORT_CONSOLE_CODE_DIR: codeDir,
    SUPPORT_CONSOLE_LOCAL: config.SUPPORT_CONSOLE_LOCAL || "",
    SUPPORT_CONSOLE_ENV: config.SUPPORT_CONSOLE_ENV || "",
    SUPPORT_CONSOLE_ALLOW_WRITER: config.SUPPORT_CONSOLE_ALLOW_WRITER || "",
    SUPPORT_DB_HOST: config.SUPPORT_DB_HOST || "",
    SUPPORT_DB_PORT: config.SUPPORT_DB_PORT || "3306",
    SUPPORT_DB_NAME: config.SUPPORT_DB_NAME || "",
    SUPPORT_DB_USER: config.SUPPORT_DB_USER || "",
    SUPPORT_DB_PASSWORD_FILE: config.SUPPORT_DB_PASSWORD_FILE || "",
  }
  const mcp = { mcpServers: { db: { type: "stdio", command: "node", args: [path.join(MACHINE_DIR, "db-mcp", "server.js")], env: dbEnv } } }
  const mcpFile = path.join(turnDir, "mcp.json")
  fs.writeFileSync(mcpFile, JSON.stringify(mcp, null, 2))

  const args = [
    "-p",
    "--output-format", "stream-json", "--verbose",
    // No Bash or other code-running tools, no user/project settings, file tools confined to cwd + --add-dir.
    "--restricted",
    "--tools", ...READ_TOOLS,
    "--permission-mode", "dontAsk",
    "--allowedTools", ...READ_TOOLS, ...DB_TOOLS,
    "--max-turns", String(config.SUPPORT_CONSOLE_MAX_TURNS || DEFAULT_MAX_TURNS),
    "--settings", settingsFile,
    "--strict-mcp-config", "--mcp-config", mcpFile,
    "--add-dir", codeDir,
    "--append-system-prompt", `${BRIEF}\n\nThe deployed code is in ${codeDir}.\n\n${turn.brief}`,
  ]
  // H3 — follow-ups resume the conversation's Claude Code session.
  if (turn.resumeId) args.push("--resume", turn.resumeId)
  args.push("--model", modelFor(turn.model, config))

  // The hook inherits this environment; the MCP server gets dbEnv from mcp.json.
  const passed = Object.fromEntries(Object.entries(config).filter(([name]) => PASS_ENV.test(name)))
  const env = { ...passed, SUPPORT_ENTITY_ID: dbEnv.SUPPORT_ENTITY_ID, SUPPORT_EVENTS_FILE: eventsFile, SUPPORT_CONSOLE_CODE_DIR: codeDir }
  if (configDir) env.CLAUDE_CONFIG_DIR = configDir
  return { bin: config.CLAUDE_BIN || "claude", args, env, cwd, codeDir, codeRev: codeRevision(codeDir), eventsFile, stdin: turn.question }
}

// @returns the git revision the code archive was built from
export function codeRevision(codeDir) {
  try {
    return fs.readFileSync(path.join(codeDir, "REVISION"), "utf8").trim()
  } catch {
    return path.basename(codeDir)
  }
}

// Where every client's Claude Code config folder sits (deployed): the relay user's home
// (/var/lib/support-console, writable under the unit's ProtectSystem=strict), outside the clients
// folder and denied to the read tools. Local mode keeps the developer's own login folder.
function configRoot(config) {
  if (config.SUPPORT_CONSOLE_LOCAL === "1") return null
  return config.SUPPORT_CONSOLE_CLAUDE_DIR || path.join(config.HOME || "/var/lib/support-console", "claude-clients")
}

// X22 — one Claude Code config folder per client, so one client's transcripts are never in another
// client's project list. @returns the folder, or null in local mode (Claude Code's default)
export function claudeConfigDir(entityId, config = process.env) {
  const root = configRoot(config)
  return root ? path.join(root, String(entityId)) : null
}

// Where Claude Code keeps a session transcript for a working directory.
export function transcriptPath(clientsDir, entityId, claudeSessionId, config = process.env) {
  const cwd = path.join(clientsDir, String(entityId))
  const base = claudeConfigDir(entityId, config) || config.CLAUDE_CONFIG_DIR || path.join(config.HOME || "", ".claude")
  return path.join(base, "projects", cwd.replace(/[^a-zA-Z0-9]/g, "-"), `${claudeSessionId}.jsonl`)
}
