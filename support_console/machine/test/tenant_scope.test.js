// Keeping Claude's SQL inside one client (openspec/changes/support-console-tenant-scope): joins only
// along real links, the deny list, the hidden scope columns and the row check. Each test is named
// "tenant-scope <ID> — …" so features/support_console/tenant_scope.feature can run it by ID.
import { test } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { prepareStatement, heldBack, withoutScope, linksFor } from "../lib/sql_rules.js"
import { loadJoinMap } from "../lib/tables.js"

// The tables with entity_id these examples use, and their links as join_map.json carries them
const SCOPED = new Set(["documents", "folders", "investors", "investments", "funds", "users", "capital_commitments",
  "capital_remittances", "capital_remittance_payments"])
const MAP = {
  links: {
    doc_shares: [{ column: "document_id", to: "documents" }],
    documents: [{ column: "folder_id", to: "folders" }],
    action_text_rich_texts: [{ column: "record_id", polymorphic: "record_type" }],
    active_storage_attachments: [{ column: "blob_id", to: "active_storage_blobs" }, { column: "record_id", polymorphic: "record_type" }],
    taggings: [{ column: "tag_id", to: "tags" }, { column: "taggable_id", polymorphic: "taggable_type" }],
    agent_chat_sessions: [{ column: "analyst_id", to: "users" }],
    agent_chat_messages: [{ column: "agent_chat_session_id", to: "agent_chat_sessions" }],
    capital_commitments: [{ column: "investor_id", to: "investors" }],
    capital_remittance_payments: [{ column: "capital_remittance_id", to: "capital_remittances" }],
  },
  classes: { investors: "Investor", documents: "Document", funds: "Fund", entities: "Entity" },
}
const run = (sql, joinMap = MAP) => prepareStatement(sql, 18, SCOPED, "IRM_staging", joinMap)
const allowed = (sql, joinMap) => {
  const result = run(sql, joinMap)
  assert.equal(result.reason, undefined, `refused: ${result.reason}`)
  return result
}
const reason = (sql, joinMap) => run(sql, joinMap).reason

// --- happy paths -----------------------------------------------------------------------------------

test("tenant-scope H1 — a real-link join runs and its hidden column is stripped", () => {
  const { sql, scopeColumns } = allowed("SELECT d.name, s.email FROM documents d JOIN doc_shares s ON s.document_id = d.id WHERE d.entity_id = 18")
  assert.deepEqual(scopeColumns, ["__scope_d"])
  assert.match(sql, /`d`\.`entity_id` AS `__scope_d`/)
  const rows = [{ name: "Q3 report", email: "lp1@x", __scope_d: 18 }]
  assert.equal(heldBack(rows, 18), false)
  assert.deepEqual(withoutScope(rows, ["name", "email", "__scope_d"]), { columns: ["name", "email"], rows: [{ name: "Q3 report", email: "lp1@x" }] })
})

test("tenant-scope H2 — investor → attachments (with its type) → blobs runs", () => {
  allowed("SELECT b.filename FROM investors i JOIN active_storage_attachments a ON a.record_type = 'Investor' AND a.record_id = i.id " +
    "JOIN active_storage_blobs b ON b.id = a.blob_id WHERE i.entity_id = 18")
})

test("tenant-scope H3 — a note joined with its record type runs", () => {
  allowed("SELECT r.body FROM investors i JOIN action_text_rich_texts r ON r.record_type = 'Investor' AND r.record_id = i.id WHERE i.entity_id = 18")
})

test("tenant-scope H4 — an investor and its LP firm: no scope column for entities, never held back", () => {
  const { scopeColumns } = allowed("SELECT i.investor_name, i.investor_entity_id, e.name, e.pan FROM investors i JOIN entities e ON e.id = i.investor_entity_id WHERE i.entity_id = 18")
  assert.deepEqual(scopeColumns, ["__scope_i"])
  assert.equal(heldBack([{ investor_name: "Ravi", investor_entity_id: 55, name: "Ravi Family Office", __scope_i: 18 }], 18), false)
})

test("tenant-scope H5 — grouped totals carry MIN/MAX scope columns", () => {
  const { sql, scopeColumns } = allowed("SELECT r.capital_call_id, SUM(p.amount_cents) FROM capital_remittances r JOIN capital_remittance_payments p " +
    "ON p.capital_remittance_id = r.id WHERE r.entity_id = 18 AND p.entity_id = 18 GROUP BY r.capital_call_id")
  assert.deepEqual(scopeColumns, ["__scope_r_min", "__scope_r_max", "__scope_p_min", "__scope_p_max"])
  assert.match(sql, /MIN\(`r`\.`entity_id`\) AS `__scope_r_min`/)
  assert.equal(heldBack([{ capital_call_id: 7, total: 900, __scope_r_min: 18, __scope_r_max: 18, __scope_p_min: 18, __scope_p_max: 18 }], 18), false)
})

test("tenant-scope H6 — an everyday lookup comes back exactly as asked", () => {
  const { sql } = allowed("SELECT id, name, due_date FROM capital_remittances WHERE entity_id = 18 AND fund_id = 323 ORDER BY id")
  assert.match(sql, /ORDER BY `id` ASC$/)
  const rows = [{ id: 1, name: "Call 1", due_date: "2026-10-01", __scope_capital_remittances: 18 }]
  assert.deepEqual(withoutScope(rows, ["id", "name", "due_date", "__scope_capital_remittances"]).columns, ["id", "name", "due_date"])
})

// --- edge cases ------------------------------------------------------------------------------------

test("tenant-scope E1 — a link written the other way round runs", () => {
  allowed("SELECT d.name, s.email FROM documents d JOIN doc_shares s ON d.id = s.document_id WHERE d.entity_id = 18")
})

test("tenant-scope E2 — IN returning the right column runs, with no scope column", () => {
  const { scopeColumns } = allowed("SELECT * FROM doc_shares WHERE document_id IN (SELECT id FROM documents WHERE entity_id = 18)")
  assert.deepEqual(scopeColumns, [])
})

test("tenant-scope E3 — commitments totalled per LP firm run", () => {
  const { scopeColumns } = allowed("SELECT e.name, SUM(c.committed_amount_cents) FROM capital_commitments c JOIN investors i ON i.id = c.investor_id " +
    "JOIN entities e ON e.id = i.investor_entity_id WHERE c.entity_id = 18 AND i.entity_id = 18 GROUP BY e.name")
  assert.deepEqual(scopeColumns, ["__scope_c_min", "__scope_c_max", "__scope_i_min", "__scope_i_max"])
})

test("tenant-scope E4 — UNION arms share positional scope columns, so rows still merge", () => {
  const { sql, scopeColumns } = allowed("SELECT name FROM documents WHERE entity_id = 18 UNION SELECT name FROM folders WHERE entity_id = 18")
  assert.deepEqual(scopeColumns, ["__scope_1"])
  assert.match(sql, /`documents`\.`entity_id` AS `__scope_1`.*UNION.*`folders`\.`entity_id` AS `__scope_1`/)
  // A NULL padding (an arm with no table that has entity_id) is skipped
  assert.equal(heldBack([{ name: "x", __scope_1: 18 }, { name: "y", __scope_1: null }], 18), false)
})

test("tenant-scope E5 — DISTINCT keeps its rows: the hidden column is the client's id on every row", () => {
  const { sql } = allowed("SELECT DISTINCT s.email FROM documents d JOIN doc_shares s ON s.document_id = d.id WHERE d.entity_id = 18")
  assert.match(sql, /^SELECT DISTINCT `s`\.`email`, `d`\.`entity_id` AS `__scope_d`/)
})

test("tenant-scope E6 — a new table is refused until the link list that carries it is published", () => {
  const sql = "SELECT c.body FROM documents d JOIN doc_comments c ON c.document_id = d.id WHERE d.entity_id = 18"
  assert.equal(reason(sql), "table not allowed")
  allowed(sql, { ...MAP, links: { ...MAP.links, doc_comments: [{ column: "document_id", to: "documents" }] } })
})

test("tenant-scope E7 — a linked table used without its link is refused, naming the link", () => {
  assert.equal(reason("SELECT * FROM doc_shares WHERE id = 5"), "join on a real relationship: doc_shares can be joined by doc_shares.document_id = documents.id")
})

test("tenant-scope E8 — a polymorphic type naming the wrong class is refused", () => {
  assert.match(reason("SELECT r.body FROM investors i JOIN action_text_rich_texts r ON r.record_type = 'Deal' AND r.record_id = i.id WHERE i.entity_id = 18"), /^join on a real relationship/)
})

test("tenant-scope E9 — a column Claude names entity_id is neither refused nor held back", () => {
  allowed("SELECT i.investor_entity_id AS entity_id, i.investor_name FROM investors i WHERE i.entity_id = 18")
  assert.equal(heldBack([{ entity_id: 55, investor_name: "Ravi", __scope_i: 18 }], 18), false)
})

test("tenant-scope E10 — tags through the investor's taggings run", () => {
  allowed("SELECT t.name FROM investors i JOIN taggings g ON g.taggable_type = 'Investor' AND g.taggable_id = i.id " +
    "JOIN tags t ON t.id = g.tag_id WHERE i.entity_id = 18")
})

test("tenant-scope E11 — an LP firm reached through another *_entity_id column runs", () => {
  const { scopeColumns } = allowed("SELECT e.name FROM investments v JOIN entities e ON e.id = v.investor_entity_id WHERE v.entity_id = 18")
  assert.deepEqual(scopeColumns, ["__scope_v"])
})

test("tenant-scope E12 — a LEFT JOIN miss returns the document; its shares' NULLs are fine", () => {
  allowed("SELECT d.name, s.email FROM documents d LEFT JOIN doc_shares s ON s.document_id = d.id WHERE d.entity_id = 18")
  assert.equal(heldBack([{ name: "Unshared", email: null, __scope_d: 18 }], 18), false)
})

test("tenant-scope E13 — an aggregate over no rows: NULL scope values are skipped", () => {
  const { scopeColumns } = allowed("SELECT COUNT(*) FROM capital_remittance_payments p WHERE p.entity_id = 18 AND p.id < 0")
  assert.deepEqual(scopeColumns, ["__scope_p_min", "__scope_p_max"])
  assert.equal(heldBack([{ "COUNT(*)": 0, __scope_p_min: null, __scope_p_max: null }], 18), false)
})

test("tenant-scope E14 — LIMIT and ORDER BY are unchanged", () => {
  const { sql } = allowed("SELECT s.email FROM documents d JOIN doc_shares s ON s.document_id = d.id WHERE d.entity_id = 18 ORDER BY s.id LIMIT 5")
  assert.match(sql, /ORDER BY `s`\.`id` ASC LIMIT 5$/)
})

// --- error cases -----------------------------------------------------------------------------------

test("tenant-scope X1 — a wrong-column join is refused before it runs, naming the link", () => {
  assert.equal(reason("SELECT s.email FROM documents d JOIN doc_shares s ON s.id = d.id WHERE d.entity_id = 18"),
    "join on a real relationship: doc_shares can be joined by doc_shares.document_id = documents.id")
  assert.match(reason("SELECT s.email FROM documents d JOIN doc_shares s ON s.document_id = d.folder_id WHERE d.entity_id = 18"), /^join on a real relationship/)
})

test("tenant-scope X2 — IN returning the wrong column is refused", () => {
  assert.match(reason("SELECT * FROM doc_shares WHERE document_id IN (SELECT folder_id FROM documents WHERE entity_id = 18)"), /^join on a real relationship/)
})

test("tenant-scope X3 — a polymorphic join without its type is refused", () => {
  assert.match(reason("SELECT r.body FROM investors i JOIN action_text_rich_texts r ON r.record_id = i.id WHERE i.entity_id = 18"), /^join on a real relationship/)
})

test("tenant-scope X4 — a table with no link to client data is not allowed", () => {
  assert.equal(reason("SELECT * FROM website_leads"), "table not allowed")
  assert.equal(reason("SELECT * FROM blogs WHERE id = 1"), "table not allowed")
  assert.deepEqual(linksFor("blogs", MAP), [])
})

test("tenant-scope X5 — AI chat logs are not allowed, though their links are real", () => {
  assert.equal(reason("SELECT m.content FROM agent_chat_messages m JOIN agent_chat_sessions s ON m.agent_chat_session_id = s.id " +
    "JOIN users u ON s.analyst_id = u.id WHERE u.entity_id = 18"), "table not allowed")
})

test("tenant-scope X6 — the LP firm's own funds are refused", () => {
  assert.equal(reason("SELECT f.name FROM investors i JOIN funds f ON f.entity_id = i.investor_entity_id WHERE i.entity_id = 18"), "add filter")
})

test("tenant-scope X8 — without join_map.json no table lacking entity_id can be read", () => {
  const empty = fs.mkdtempSync(path.join(os.tmpdir(), "no-map-"))
  const joinMap = loadJoinMap(empty)
  assert.deepEqual(joinMap, { links: {}, classes: {} })
  assert.equal(reason("SELECT d.name, s.email FROM documents d JOIN doc_shares s ON s.document_id = d.id WHERE d.entity_id = 18", joinMap), "table not allowed")
})

test("tenant-scope X9 — the __scope_ prefix is reserved", () => {
  assert.equal(reason("SELECT d.id AS __scope_d FROM documents d WHERE d.entity_id = 18"), "unreadable")
  assert.equal(reason("SELECT __scope_x FROM documents WHERE entity_id = 18"), "unreadable")
})

test("tenant-scope X10 — a shape the rewrite cannot extend (EXCEPT, INTERSECT) is refused", () => {
  assert.equal(reason("SELECT name FROM documents WHERE entity_id = 18 EXCEPT SELECT name FROM folders WHERE entity_id = 18"), "unreadable")
  assert.equal(reason("SELECT name FROM documents WHERE entity_id = 18 INTERSECT SELECT name FROM folders WHERE entity_id = 18"), "unreadable")
})

test("tenant-scope X11 — a row from another client holds back the whole result", () => {
  assert.equal(heldBack([{ name: "Q3 report", __scope_d: 18 }, { name: "Beta side letter", __scope_d: 31 }], 18), true)
  assert.equal(heldBack([{ total: 5, __scope_p_min: 18, __scope_p_max: 31 }], 18), true)
  assert.equal(heldBack([{ name: "x", __scope_1: "31" }], "18"), true)
})
