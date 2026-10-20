// Two firms in a throwaway MySQL (container support-canary, port 33099 — see README.md). Client 18 is Golden
// Angels; firm 31 is Canary Capital, whose every text value carries CANARY. Thousands of random
// queries go through the CURRENT checker; every query it allows is run, and any row containing
// CANARY is a leak. Each query is also judged by the prototype join map (option 1) to show whether
// the new rule would have refused it.
import fs from "node:fs"
import { createRequire } from "node:module"
import { prepareStatement } from "../machine/lib/sql_rules.js"
const require = createRequire(new URL("../machine/package.json", import.meta.url))
const mysql = require("mysql2/promise")

const scoped = new Set(["investors", "funds", "documents", "folders", "users", "capital_remittances", "capital_remittance_payments"])
const db = await mysql.createConnection({ host: "127.0.0.1", port: 33099, user: "root", password: "canary", database: "canary", multipleStatements: true })

// --- schema and seed: ids interleave, so a wrong join lands on the other firm's rows -------------
await db.query(`
DROP TABLE IF EXISTS entities, investors, funds, documents, folders, users, doc_shares, action_text_rich_texts,
  active_storage_attachments, active_storage_blobs, agent_chat_sessions, agent_chat_messages, taggings, tags,
  capital_remittances, capital_remittance_payments;
CREATE TABLE entities (id INT PRIMARY KEY, name VARCHAR(50));
CREATE TABLE investors (id INT PRIMARY KEY, entity_id INT, investor_entity_id INT, investor_name VARCHAR(50));
CREATE TABLE funds (id INT PRIMARY KEY, entity_id INT, name VARCHAR(50));
CREATE TABLE folders (id INT PRIMARY KEY, entity_id INT, name VARCHAR(50));
CREATE TABLE documents (id INT PRIMARY KEY, entity_id INT, folder_id INT, name VARCHAR(50));
CREATE TABLE users (id INT PRIMARY KEY, entity_id INT, email VARCHAR(50));
CREATE TABLE doc_shares (id INT PRIMARY KEY, document_id INT, email VARCHAR(50), view_count INT);
CREATE TABLE action_text_rich_texts (id INT PRIMARY KEY, record_type VARCHAR(30), record_id INT, body VARCHAR(80));
CREATE TABLE active_storage_blobs (id INT PRIMARY KEY, filename VARCHAR(50));
CREATE TABLE active_storage_attachments (id INT PRIMARY KEY, record_type VARCHAR(30), record_id INT, blob_id INT);
CREATE TABLE agent_chat_sessions (id INT PRIMARY KEY, analyst_id INT, chattable_type VARCHAR(30), chattable_id INT);
CREATE TABLE agent_chat_messages (id INT PRIMARY KEY, agent_chat_session_id INT, content VARCHAR(80));
CREATE TABLE tags (id INT PRIMARY KEY, name VARCHAR(30));
CREATE TABLE taggings (id INT PRIMARY KEY, tag_id INT, taggable_type VARCHAR(30), taggable_id INT);
CREATE TABLE capital_remittances (id INT PRIMARY KEY, entity_id INT, fund_id INT, notes VARCHAR(50));
CREATE TABLE capital_remittance_payments (id INT PRIMARY KEY, entity_id INT, capital_remittance_id INT, reference_no VARCHAR(50));
`)
const ins = (t, rows) => rows.length && db.query(`INSERT INTO ${t} VALUES ?`, [rows])
const firm = (id) => id % 2 === 1 ? 18 : 31            // odd ids: Golden Angels, even ids: Canary Capital
const tag = (id, text) => firm(id) === 31 ? `CANARY ${text} ${id}` : `${text} ${id}`
const ids = [...Array(40).keys()].map((i) => i + 1)
await ins("entities", [[18, "Golden Angels"], [31, "CANARY Capital"], [55, "Ravi Family Office"]])
await ins("investors", ids.map((i) => [i, firm(i), 55, tag(i, "investor")]))
await ins("funds", ids.map((i) => [i, firm(i), tag(i, "fund")]))
await ins("folders", ids.map((i) => [i, firm(i), tag(i, "folder")]))
await ins("documents", ids.map((i) => [i, firm(i), i, tag(i, "doc")]))
await ins("users", ids.map((i) => [i, firm(i), tag(i, "user@x")]))
// Tables without entity_id number their own rows one higher (k = i + 1), as in a real database where
// ids never line up across tables — so a wrong `id = id` join lands on the other firm's row.
const k = (i) => i + 1
await ins("doc_shares", ids.map((i) => [k(i), i, tag(i, "lp@x"), k(i)]))                 // share k(i) belongs to document i
await ins("action_text_rich_texts", ids.flatMap((i) => [[k(i), "Investor", i, tag(i, "note")], [100 + i, "Deal", i, `CANARY deal note ${i}`]]))
await ins("active_storage_blobs", ids.map((i) => [k(i), tag(i, "file.pdf")]))
await ins("active_storage_attachments", ids.map((i) => [k(i), "Investor", i, k(i)]))
await ins("agent_chat_sessions", ids.map((i) => [k(i), i, "Entity", firm(i)]))
await ins("agent_chat_messages", ids.map((i) => [k(i), k(i), tag(i, "chat")]))
await ins("tags", ids.map((i) => [k(i), `tag ${i}`]))
await ins("taggings", ids.map((i) => [k(i), k(i), "Investor", i]))
await ins("capital_remittances", ids.map((i) => [i, firm(i), i, tag(i, "remit")]))
await ins("capital_remittance_payments", ids.map((i) => [i, firm(i), i, tag(i, "pay")]))

// --- the prototype join map (option 1), for these tables -----------------------------------------
const LINKS = {
  doc_shares: [["document_id", "documents"]], documents: [["folder_id", "folders"]],
  active_storage_attachments: [["blob_id", "active_storage_blobs"], ["record_id", "poly:record_type"]],
  action_text_rich_texts: [["record_id", "poly:record_type"]], taggings: [["tag_id", "tags"], ["taggable_id", "poly:taggable_type"]],
  agent_chat_sessions: [["analyst_id", "users"], ["chattable_id", "poly:chattable_type"]],
  agent_chat_messages: [["agent_chat_session_id", "agent_chat_sessions"]],
  capital_remittance_payments: [["capital_remittance_id", "capital_remittances"]], capital_remittances: [["fund_id", "funds"]],
}
const CLASS = { investors: "Investor", entities: "Entity", funds: "Fund", documents: "Document" }
// The same links in join_map.json's shape, for the checker
const JOIN_MAP = {
  links: Object.fromEntries(Object.entries(LINKS).map(([table, list]) => [table, list.map(([column, to]) =>
    to.startsWith("poly:") ? { column, polymorphic: to.slice(5) } : { column, to })])),
  classes: CLASS,
}
const DENIED = new Set(["agent_chat_sessions", "agent_chat_messages"])
const COLS = {
  investors: ["id", "investor_entity_id"], funds: ["id"], folders: ["id"], documents: ["id", "folder_id"], users: ["id"],
  doc_shares: ["id", "document_id", "view_count"], action_text_rich_texts: ["id", "record_id"], active_storage_blobs: ["id"],
  active_storage_attachments: ["id", "record_id", "blob_id"], agent_chat_sessions: ["id", "analyst_id", "chattable_id"],
  agent_chat_messages: ["id", "agent_chat_session_id"], tags: ["id"], taggings: ["id", "tag_id", "taggable_id"],
  capital_remittances: ["id", "fund_id"], capital_remittance_payments: ["id", "capital_remittance_id"],
}
const UNSCOPED = Object.keys(COLS).filter((t) => !scoped.has(t))
const POLY_TYPE = { action_text_rich_texts: "record_type", active_storage_attachments: "record_type", taggings: "taggable_type", agent_chat_sessions: "chattable_type" }

// Is "child.col = parent.pcol" (with an optional pinned type) a real link?
function realLink(child, col, parent, pcol, type) {
  for (const [c, to] of LINKS[child] || []) {
    if (c !== col || pcol !== "id") continue
    if (to === parent) return true
    if (to.startsWith("poly:") && type === CLASS[parent]) return true
  }
  for (const [c, to] of LINKS[parent] || []) if (c === pcol && col === "id" && to === child) return true
  return false
}

// --- random queries -------------------------------------------------------------------------------
// mulberry32: small, seeded, and even across every bit (the earlier LCG cycled through few tables)
let seed = 7
const next = () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
const rand = (n) => Math.floor(next() * n)
const pick = (a) => a[rand(a.length)]
const results = { allowed: 0, leaked: 0, leakedReal: 0, leakedNotReal: 0, allowedReal: 0, refused: 0, shapes: {} }
const N = 4000
for (let n = 0; n < N; n++) {
  const base = pick(["investors", "documents", "users", "funds", "capital_remittances"])
  const other = pick(UNSCOPED)
  const bcol = pick(COLS[base]); const ocol = pick(COLS[other])
  const pinType = POLY_TYPE[other] && rand(2) ? pick(["Investor", "Deal", "Document", "Entity", "Fund"]) : null
  const pin = pinType ? ` AND o.${POLY_TYPE[other]} = '${pinType}'` : ""
  const form = rand(3)
  const sql = form === 2
    ? `SELECT o.* FROM ${other} o WHERE o.${ocol} IN (SELECT b.${bcol} FROM ${base} b WHERE b.entity_id = 18)${pin}`
    : `SELECT b.*, o.* FROM ${base} b JOIN ${other} o ON o.${ocol} = b.${bcol}${pin} WHERE b.entity_id = 18`
  const real = !DENIED.has(other) && realLink(other, ocol, base, bcol, pinType)
  const r = prepareStatement(sql, 18, scoped, "canary", JOIN_MAP)
  if (r.reason) { results.refused++; continue }
  results.allowed++
  if (real) results.allowedReal++
  const [rows] = await db.query(r.sql)
  const leak = rows.some((row) => Object.values(row).some((v) => typeof v === "string" && v.includes("CANARY")))
  if (leak) {
    results.leaked++
    real ? results.leakedReal++ : results.leakedNotReal++
    const shape = `${other}.${ocol} = ${base}.${bcol}${pinType ? ` [${pinType}]` : ""}${form === 2 ? " (IN)" : ""}`
    results.shapes[shape] = (results.shapes[shape] || 0) + 1
  }
}
await db.end()
console.log(`${N} random queries: ${results.refused} refused, ${results.allowed} allowed by the checker`)
console.log(`  leaked CANARY rows:                  ${results.leaked}`)
console.log(`  …of which used a real link (opt. 1 would allow): ${results.leakedReal}`)
console.log(`  …of which did NOT use a real link (opt. 1 would refuse): ${results.leakedNotReal}`)
console.log(`  allowed queries that used a real link: ${results.allowedReal} (these must stay allowed)`)
console.log(`\nleaking shapes (top 15):`)
Object.entries(results.shapes).sort((a, b) => b[1] - a[1]).slice(0, 15).forEach(([s, c]) => console.log(`  ${String(c).padStart(4)}  ${s}`))
const byTable = {}
for (const [s, c] of Object.entries(results.shapes)) byTable[s.split(".")[0]] = (byTable[s.split(".")[0]] || 0) + c
console.log("\nleaks by table:", byTable)
fs.writeFileSync(new URL("./out/canary_result.json", import.meta.url), JSON.stringify(results, null, 2))
