// Hostile queries (and a few legitimate controls) straight against the SQL checker,
// support_console/machine/lib/sql_rules.js. Each entry says what the checker should do:
//   refuse — "LEAK" when it is let through;  allow — "OVER-BLOCKED" when it is refused.
// Exits 1 on any mismatch. Uses the real link list (out/join_map.json, from build_join_map.rb).
import fs from "node:fs"
import { prepareStatement } from "../machine/lib/sql_rules.js"

const scoped = new Set(JSON.parse(fs.readFileSync(new URL("./out/tables_with_entity_id.json", import.meta.url))))
const joinMap = JSON.parse(fs.readFileSync(new URL("./out/join_map.json", import.meta.url)))
const C = 18
const attacks = [
  // Wrong-column joins and IN (the known gap)
  ["wrong join id=id", "SELECT s.email FROM documents d JOIN doc_shares s ON s.id = d.id WHERE d.entity_id = 18"],
  ["wrong join fk=other", "SELECT s.email FROM documents d JOIN doc_shares s ON s.document_id = d.folder_id WHERE d.entity_id = 18"],
  ["IN wrong column", "SELECT * FROM doc_shares WHERE document_id IN (SELECT folder_id FROM documents WHERE entity_id = 18)"],
  ["polymorphic without type", "SELECT r.body FROM investors i JOIN action_text_rich_texts r ON r.record_id = i.id WHERE i.entity_id = 18"],
  ["polymorphic wrong type", "SELECT r.body FROM investors i JOIN action_text_rich_texts r ON r.record_type = 'Deal' AND r.record_id = i.id WHERE i.entity_id = 18"],
  ["chat logs via users", "SELECT m.content FROM agent_chat_messages m JOIN agent_chat_sessions s ON m.agent_chat_session_id = s.id JOIN users u ON s.analyst_id = u.id WHERE u.entity_id = 18"],
  ["chat logs via wrong join", "SELECT m.content FROM investors i JOIN agent_chat_messages m ON m.id = i.id WHERE i.entity_id = 18"],
  ["blobs two hops wrong", "SELECT b.filename FROM documents d JOIN active_storage_blobs b ON b.id = d.id WHERE d.entity_id = 18"],
  ["join on non-key equality", "SELECT s.email FROM documents d JOIN doc_shares s ON s.view_count = d.id WHERE d.entity_id = 18"],
  ["join on created_at", "SELECT s.email FROM documents d JOIN doc_shares s ON s.created_at = d.created_at WHERE d.entity_id = 18"],
  // Weakened filters on scoped tables
  ["OR 1=1", "SELECT * FROM investors WHERE entity_id = 18 OR 1=1"],
  ["OR other client", "SELECT * FROM investors WHERE entity_id = 18 OR entity_id = 31"],
  ["IN two clients", "SELECT * FROM investors WHERE entity_id IN (18, 31)"],
  ["BETWEEN", "SELECT * FROM investors WHERE entity_id BETWEEN 18 AND 31"],
  ["string id", "SELECT * FROM investors WHERE entity_id = '31'"],
  ["greater than", "SELECT * FROM investors WHERE entity_id > 17"],
  ["not equal", "SELECT * FROM investors WHERE entity_id <> 18"],
  ["filter only in HAVING", "SELECT entity_id, COUNT(*) FROM investors GROUP BY entity_id HAVING entity_id = 18"],
  ["filter in LEFT JOIN ON only", "SELECT f.name FROM funds f LEFT JOIN investors i ON i.entity_id = 18 AND i.id = f.id"],
  ["RIGHT JOIN", "SELECT f.name FROM investors i RIGHT JOIN funds f ON f.id = i.id WHERE i.entity_id = 18"],
  ["comma join unscoped", "SELECT f.name FROM investors i, funds f WHERE i.entity_id = 18"],
  ["NATURAL JOIN", "SELECT * FROM investors i NATURAL JOIN funds f WHERE i.entity_id = 18"],
  ["USING", "SELECT * FROM investors i JOIN funds f USING (id) WHERE i.entity_id = 18"],
  ["self join other client", "SELECT b.investor_name FROM investors a JOIN investors b ON b.id = a.id + 1 WHERE a.entity_id = 18"],
  // Hiding tables
  ["UNION unscoped arm", "SELECT investor_name FROM investors WHERE entity_id = 18 UNION SELECT investor_name FROM investors"],
  ["UNION ALL other client", "SELECT investor_name FROM investors WHERE entity_id = 18 UNION ALL SELECT name FROM funds WHERE entity_id = 31"],
  ["CTE shadowing", "WITH investors AS (SELECT * FROM investors) SELECT * FROM investors"],
  ["CTE named like table, filter outside", "WITH x AS (SELECT * FROM investors) SELECT * FROM x WHERE entity_id = 18"],
  ["derived table unscoped", "SELECT * FROM (SELECT * FROM investors) t WHERE t.entity_id = 18"],
  ["scalar subquery unscoped", "SELECT (SELECT COUNT(*) FROM investors) n FROM funds WHERE entity_id = 18"],
  ["EXISTS unscoped", "SELECT name FROM funds f WHERE f.entity_id = 18 AND EXISTS (SELECT 1 FROM investors)"],
  ["correlated subquery other", "SELECT name, (SELECT MAX(investor_name) FROM investors i WHERE i.entity_id = 31) FROM funds WHERE entity_id = 18"],
  // Other schemas and system data
  ["information_schema", "SELECT * FROM information_schema.tables"],
  ["mysql.user", "SELECT user, authentication_string FROM mysql.user"],
  ["performance_schema", "SELECT * FROM performance_schema.threads"],
  ["other database", "SELECT * FROM IRM_production.investors WHERE entity_id = 18"],
  ["sys schema", "SELECT * FROM sys.session"],
  // Statements and side effects
  ["multi-statement", "SELECT * FROM investors WHERE entity_id = 18; SELECT * FROM investors"],
  ["INTO OUTFILE", "SELECT * FROM investors WHERE entity_id = 18 INTO OUTFILE '/tmp/x'"],
  ["variable assign", "SELECT @x := 31"],
  ["variable read", "SELECT * FROM investors WHERE entity_id = @client"],
  ["SHOW", "SHOW TABLES"],
  ["EXPLAIN", "EXPLAIN SELECT * FROM investors"],
  ["UPDATE", "UPDATE investors SET investor_name = 'x' WHERE entity_id = 18"],
  ["sleep", "SELECT SLEEP(10) FROM investors WHERE entity_id = 18"],
  ["load_file", "SELECT LOAD_FILE('/etc/passwd') FROM investors WHERE entity_id = 18"],
  ["FOR UPDATE lock", "SELECT * FROM investors WHERE entity_id = 18 FOR UPDATE"],
  // Quoting and comments
  ["comment hides OR", "SELECT * FROM investors WHERE entity_id = 18 /* */ OR /* */ 1=1"],
  ["hash comment", "SELECT * FROM investors WHERE entity_id = 18 # \n OR 1=1"],
  ["backtick alias trick", "SELECT `i`.investor_name FROM investors `i` JOIN funds `f` ON `f`.id = `i`.id WHERE `i`.entity_id = 18"],
  ["string with entity_id", "SELECT * FROM investors WHERE investor_name = 'entity_id = 18'"],
  ["denied table", "SELECT * FROM api_tokens"],
  ["denied table joined", "SELECT t.* FROM users u JOIN otp_deliveries t ON t.user_id = u.id WHERE u.entity_id = 18"],
  // Entities table
  ["entities other id", "SELECT * FROM entities WHERE id = 31"],
  ["entities via wrong column", "SELECT e.* FROM investors i JOIN entities e ON e.id = i.id WHERE i.entity_id = 18"],
  ["entities pivot to LP funds", "SELECT f.name FROM investors i JOIN funds f ON f.entity_id = i.investor_entity_id WHERE i.entity_id = 18"],
  // Functions and odd syntax
  ["JSON_TABLE", "SELECT * FROM investors i, JSON_TABLE(i.json_fields, '$[*]' COLUMNS (v INT PATH '$')) j WHERE i.entity_id = 18"],
  ["LATERAL", "SELECT * FROM investors i, LATERAL (SELECT * FROM funds) f WHERE i.entity_id = 18"],
]
// Legitimate questions that must keep working.
const controls = [
  ["real link: shares of a document", "SELECT d.name, s.email FROM documents d JOIN doc_shares s ON s.document_id = d.id WHERE d.entity_id = 18"],
  ["real link via IN", "SELECT * FROM doc_shares WHERE document_id IN (SELECT id FROM documents WHERE entity_id = 18)"],
  ["polymorphic with its type", "SELECT r.body FROM investors i JOIN action_text_rich_texts r ON r.record_type = 'Investor' AND r.record_id = i.id WHERE i.entity_id = 18"],
  ["LP firm name via investor_entity_id", "SELECT i.investor_name, e.name FROM investors i JOIN entities e ON e.id = i.investor_entity_id WHERE i.entity_id = 18"],
  ["window over the client's rows", "SELECT investor_name, COUNT(*) OVER () FROM investors WHERE entity_id = 18"],
  ["grouped totals", "SELECT r.capital_call_id, SUM(p.amount_cents) FROM capital_remittances r JOIN capital_remittance_payments p ON p.capital_remittance_id = r.id WHERE r.entity_id = 18 AND p.entity_id = 18 GROUP BY r.capital_call_id"],
]

let mismatches = 0
const run = (list, expect) => {
  for (const [name, sql] of list) {
    let reason
    try {
      reason = prepareStatement(sql, C, scoped, "IRM_staging", joinMap).reason ?? null
    } catch (e) {
      reason = `error: ${e.message.slice(0, 40)}`
    }
    const ok = expect === "refuse" ? reason !== null : reason === null
    if (!ok) mismatches++
    const mark = ok ? "✓" : expect === "refuse" ? "✗ LEAK        " : "✗ OVER-BLOCKED"
    console.log(`${mark.padEnd(15)} ${name.padEnd(38)} ${reason ? `refused (${reason})` : "allowed"}`)
  }
}
console.log("— should be refused —")
run(attacks, "refuse")
console.log("\n— should be allowed —")
run(controls, "allow")
console.log(`\n${attacks.length + controls.length} queries, ${mismatches} not as expected`)
process.exit(mismatches ? 1 : 0)
