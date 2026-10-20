// Replays every SQL statement Claude ran (out/staging_queries.json, from export_queries.rb) through the CURRENT checker, and list the
// tables without entity_id each one touches (the only tables option 1 changes the rule for).
import fs from "node:fs"
import { createRequire } from "node:module"
import { prepareStatement } from "../machine/lib/sql_rules.js"
const require = createRequire(new URL("../machine/package.json", import.meta.url))
const { Parser } = require("node-sql-parser/build/mysql.js")

const scoped = new Set(JSON.parse(fs.readFileSync(new URL("./out/tables_with_entity_id.json", import.meta.url))))
const joinMap = JSON.parse(fs.readFileSync(new URL("./out/join_map.json", import.meta.url)))
const queries = JSON.parse(fs.readFileSync(new URL("./out/staging_queries.json", import.meta.url)))
const parser = new Parser()
let unchanged = 0
for (const q of queries) {
  const now = prepareStatement(q.sql, q.entity_id, scoped, "IRM_staging", joinMap)
  const tables = [...new Set(parser.tableList(q.sql, { database: "MySQL" }).map((t) => t.split("::")[2]))]
  const unscoped = tables.filter((t) => !scoped.has(t) && t !== "entities")
  // With no table outside entity_id + entities, option 1 has nothing to change
  const affected = unscoped.length > 0
  if (!affected) unchanged++
  console.log(`#${q.id} recorded=${q.outcome} replay=${now.reason ? "refused: " + now.reason : "allowed"}  tables=${tables.join(",")}${affected ? "  → uses tables without entity_id: " + unscoped.join(",") : "  → option 1 changes nothing"}`)
}
console.log(`\n${queries.length} staging queries; ${unchanged} touch only entity_id tables (+ entities), so options 1 and 2 cannot change their outcome`)
