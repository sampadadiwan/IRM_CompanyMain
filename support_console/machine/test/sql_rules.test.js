// The scope rules shared by the hook and the db MCP server (design card ⑥).
import { test } from "node:test"
import assert from "node:assert/strict"
import { checkStatement, prepareStatement, heldBack } from "../lib/sql_rules.js"

const tables = new Set(["capital_calls", "account_entries", "investors", "funds", "users", "form_types"])
// tenant-scope ③ — a table without entity_id is tied only along a link from join_map.json
const links = { links: { form_custom_fields: [{ column: "form_type_id", to: "form_types" }] }, classes: {} }
const check = (sql) => checkStatement(sql, 18, tables, "IRM_production", links)

test("allows a scoped SELECT", () => {
  assert.equal(check("SELECT * FROM capital_calls WHERE entity_id = 18 LIMIT 5"), null)
  assert.equal(check("SELECT c.id FROM capital_calls c WHERE c.entity_id IN (18)"), null)
  assert.equal(check("SELECT c.id FROM capital_calls c WHERE c.entity_id = '18' AND c.id > 3"), null)
  assert.equal(check("WITH x AS (SELECT * FROM investors WHERE entity_id = 18) SELECT * FROM x"), null)
  assert.equal(check("SELECT f.name, SUM(c.amount_cents) FROM funds f JOIN capital_calls c ON c.fund_id = f.id AND c.entity_id = 18 WHERE f.entity_id = 18 GROUP BY f.name"), null)
  assert.equal(check("SELECT * FROM IRM_production.funds WHERE entity_id = 18"), null)
})

test("the client's own entity row, and entities reached through an *entity_id column", () => {
  assert.equal(check("SELECT name FROM entities WHERE id = 18"), null)
  assert.equal(check("SELECT i.investor_name, e.name FROM investors i JOIN entities e ON e.id = i.investor_entity_id WHERE i.entity_id = 18"), null)
  assert.equal(check("SELECT * FROM entities"), "add filter")
  assert.equal(check("SELECT f.name, e.name FROM funds f JOIN entities e ON e.id = f.id WHERE f.entity_id = 18"), "add filter")
})

test("a table without entity_id is allowed when joined or IN-linked to a scoped one", () => {
  assert.equal(check("SELECT ff.name FROM form_custom_fields ff JOIN form_types t ON ff.form_type_id = t.id WHERE t.entity_id = 18"), null)
  assert.equal(check("SELECT name FROM form_custom_fields WHERE form_type_id IN (SELECT id FROM form_types WHERE entity_id = 18)"), null)
  assert.equal(check("SELECT f.name, (SELECT COUNT(*) FROM form_custom_fields x WHERE x.form_type_id = f.id) FROM form_types f WHERE f.entity_id = 18"), null)
})

test("E13 — blocks an unscoped table", () => {
  assert.equal(check("SELECT * FROM capital_calls"), "add filter")
  assert.equal(check("SELECT * FROM capital_calls -- WHERE entity_id = 18"), "add filter")
})

test("E14 — blocks another client's id", () => {
  assert.equal(check("SELECT * FROM capital_calls WHERE entity_id = 25"), "other client")
  assert.equal(check("SELECT * FROM capital_calls WHERE entity_id IN (18, 25)"), "other client")
  assert.equal(check("SELECT * FROM capital_calls WHERE entity_id = 18 AND 25 = entity_id"), "other client")
  assert.equal(check("SELECT * FROM capital_calls WHERE entity_id = '25'"), "other client")
  assert.equal(check("SELECT * FROM capital_calls WHERE entity_id = (25)"), "other client")
  assert.equal(check("SELECT * FROM capital_calls WHERE entity_id BETWEEN 1 AND 99"), "other client")
})

test("E16 — blocks anything but one SELECT", () => {
  assert.equal(check("UPDATE capital_calls SET amount = 0 WHERE entity_id = 18"), "SELECT only")
  assert.equal(check("SELECT 1; DROP TABLE users"), "SELECT only")
  assert.equal(check("SELECT @x := 1"), "SELECT only")
  assert.equal(check("SELECT @@hostname FROM funds WHERE entity_id = 18"), "SELECT only")
  assert.equal(check("SELECT id INTO @x FROM investors WHERE entity_id = 18"), "SELECT only")
  assert.equal(check("SELECT * FROM investors WHERE entity_id = 18 INTO OUTFILE '/tmp/x'"), "SELECT only")
})

// X20 — Error case: locking reads, file reads, waits and WITH … DELETE are refused even when scoped
test("X20 — locking reads, file and wait functions, WITH … DELETE", () => {
  assert.equal(check("SELECT * FROM funds WHERE entity_id = 18 FOR UPDATE"), "SELECT only")
  // The parser does not read FOR SHARE at all, so it is refused as unreadable.
  assert.notEqual(check("SELECT * FROM funds WHERE entity_id = 18 FOR SHARE"), null)
  assert.equal(check("SELECT * FROM funds WHERE entity_id = 18 LOCK IN SHARE MODE"), "SELECT only")
  assert.equal(check("SELECT LOAD_FILE('/etc/passwd') FROM funds WHERE entity_id = 18"), "SELECT only")
  assert.equal(check("SELECT SLEEP(60) FROM funds WHERE entity_id = 18"), "SELECT only")
  assert.equal(check("SELECT BENCHMARK(1e9, MD5('a')) FROM funds WHERE entity_id = 18"), "SELECT only")
  assert.notEqual(check("WITH x AS (SELECT 1) DELETE FROM funds WHERE entity_id = 18"), null)
})

// X10 — Error case: an OR at the top of the WHERE anchors nothing, so `OR 1=1` is refused
test("X10 — OR 1=1 is refused; the row check still catches foreign rows", () => {
  assert.equal(check("SELECT * FROM capital_calls WHERE entity_id = 18 OR 1=1"), "add filter")
  assert.equal(check("SELECT * FROM capital_calls WHERE (entity_id = 18 OR id > 0) AND id < 10"), "add filter")
  // tenant-scope ⑦ — judged by the hidden scope columns, not by any column named entity_id
  assert.equal(heldBack([{ __scope_c: 18 }, { __scope_c: 25 }], 18), true)
  assert.equal(heldBack([{ entity_id: 25, __scope_c: 18 }], 18), false)
})

// X15 — Error case: a comment marker inside a string cannot hide the rest of the statement from the checks
test("X15 — # or -- inside a string is text, not a comment", () => {
  const sql = "SELECT name FROM funds WHERE entity_id = 18 AND name <> '#' UNION SELECT pan FROM investors WHERE entity_id = 25"
  assert.equal(check(sql), "other client")
  assert.equal(check("SELECT * FROM investors WHERE entity_id = 18 AND investor_name = 'Fund #1'"), null)
  assert.equal(check("SELECT * FROM investors WHERE entity_id = 18 AND notes = 'a -- b'"), null)
  assert.equal(check("SELECT 1 FROM investors WHERE entity_id = 18 -- trailing"), null)
  assert.equal(check("SELECT id FROM users WHERE entity_id = 18 AND email = 'fm1@acefund.com'"), null)
})

// X16 — Error case: quoting the checker reads differently from MySQL cannot hide a filter; what runs is rebuilt from the checked parse
test("X16 — a backslash in a backtick identifier does not hide a comment", () => {
  assert.equal(check("SELECT id AS `x\\`, name FROM funds # ` WHERE entity_id = 18"), "add filter")
  // Executable comments are dropped from the statement that runs, not executed.
  const prepared = prepareStatement("SELECT /*! 1, */ name FROM funds WHERE entity_id = 18", 18, tables)
  assert.equal(prepared.reason, undefined)
  assert.doesNotMatch(prepared.sql, /\/\*/)
  assert.equal(check("SELEC name FROM funds"), "unreadable")
})

// X17 — Error case: every SELECT in the statement needs its own filter — UNION arms, subqueries, derived tables, CTEs
test("X17 — each UNION arm, subquery, derived table and CTE is checked on its own", () => {
  assert.equal(check("SELECT name FROM funds WHERE entity_id = 18 UNION SELECT name FROM funds"), "add filter")
  assert.equal(check("SELECT * FROM funds WHERE entity_id = 18 AND id IN (SELECT fund_id FROM capital_calls)"), "add filter")
  assert.equal(check("SELECT * FROM (SELECT * FROM funds) d WHERE d.entity_id = 18"), "add filter")
  assert.equal(check("WITH x AS (SELECT * FROM investors) SELECT * FROM x"), "add filter")
  assert.equal(check("SELECT * FROM funds WHERE entity_id = 18 AND EXISTS (SELECT 1 FROM users)"), "add filter")
})

// X18 — Error case: a second table in a comma join or a loose join needs its own tie to the client
test("X18 — comma joins, loose joins and RIGHT JOIN", () => {
  assert.equal(check("SELECT * FROM funds f, users u WHERE f.entity_id = 18"), "add filter")
  assert.equal(check("SELECT * FROM funds f JOIN users u ON 1 = 1 WHERE f.entity_id = 18"), "add filter")
  assert.equal(check("SELECT * FROM funds f LEFT JOIN capital_calls c ON c.fund_id = f.id WHERE f.entity_id = 18"), "add filter")
  assert.equal(check("SELECT * FROM funds f LEFT JOIN capital_calls c ON c.fund_id = f.id AND c.entity_id = 18 WHERE f.entity_id = 18"), null)
  assert.equal(check("SELECT * FROM funds f RIGHT JOIN capital_calls c ON c.fund_id = f.id AND f.entity_id = 18 WHERE c.entity_id = 18"), "add filter")
  assert.equal(check("SELECT * FROM form_custom_fields"), "join on a real relationship: form_custom_fields can be joined by form_custom_fields.form_type_id = form_types.id")
})

// X19 — Error case: secret and cross-client tables, and other schemas, are refused outright
test("X19 — denied tables and other schemas", () => {
  assert.equal(check("SELECT token FROM api_tokens WHERE id IN (SELECT id FROM users WHERE entity_id = 18)"), "table not allowed")
  assert.equal(check("SELECT * FROM audits WHERE auditable_id = 5"), "table not allowed")
  assert.equal(check("SELECT * FROM information_schema.processlist"), "table not allowed")
  assert.equal(check("SELECT * FROM mysql.user"), "table not allowed")
  assert.equal(check("SELECT * FROM other_db.funds WHERE entity_id = 18"), "table not allowed")
})
