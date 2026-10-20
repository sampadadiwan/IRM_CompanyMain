// Client scoping rules for the Support Console (design card ⑥), shared by the PreToolUse hook
// (hooks/scope_guard.js) and the db MCP server (db-mcp/server.js).
//
// The statement is parsed as MySQL (node-sql-parser), the parse tree is checked, and the SQL that
// runs is rebuilt from that same tree (prepareStatement). Reading SQL as text let quoting tricks
// show the checker one statement and MySQL another (X16); with the rebuilt SQL the statement MySQL
// runs is, by construction, the one that was checked. Anything the parser cannot read is refused.
//
// Every SELECT in the statement — each UNION arm, subquery, derived table and CTE — is checked on its
// own (X17). In each one, every table must be tied to this client by a top-level AND condition:
//   - a table with entity_id:  <alias>.entity_id = <client>
//   - entities:                <alias>.id = <client>, or equal to an anchored table's *entity_id column
//   - any other table:         a column equal to a column of an anchored table (a join), or
//                              <alias>.<col> IN (<a SELECT that is itself anchored>)
// Secret and cross-client tables (DENIED_TABLES) are refused whatever the conditions.
// Known gap: a join on the wrong column (`child.x_id = parent.id` with the wrong x) still passes;
// flagRows and the query record catch rows that come back from another client, and v2 tenant views
// close it.
import pkg from "node-sql-parser/build/mysql.js"
import { DENIED_TABLES } from "./tables.js"

const { Parser } = pkg
const parser = new Parser()
const OPTIONS = { database: "MySQL" }

// Functions that read files, wait, or take locks — none of them answer a support question.
const DENIED_FUNCTIONS = new Set([
  "load_file", "sleep", "benchmark", "get_lock", "release_lock", "release_all_locks", "is_free_lock",
  "is_used_lock", "master_pos_wait", "source_pos_wait", "wait_for_executed_gtid_set",
  "wait_until_sql_thread_after_gtids",
])

class Refusal extends Error {}
const refuse = (reason) => { throw new Refusal(reason) }

// @returns {{sql: string}} the statement to execute, or {{reason: string}} why it is refused
export function prepareStatement(sql, entityId, tablesWithEntityId, database = null) {
  try {
    // Check the statement Claude sent, rebuild it, then check the rebuilt text too: a rebuild that
    // dropped a condition would be refused rather than run unscoped.
    const ast = parse(sql)
    checkTree(ast, String(entityId), tablesWithEntityId, database)
    const rebuilt = parser.sqlify(ast, OPTIONS)
    checkTree(parse(rebuilt), String(entityId), tablesWithEntityId, database)
    return { sql: rebuilt }
  } catch (error) {
    if (error instanceof Refusal) return { reason: error.message }
    throw error
  }
}

// @returns {string|null} why the statement is refused, or null when it may run
export function checkStatement(sql, entityId, tablesWithEntityId, database = null) {
  return prepareStatement(sql, entityId, tablesWithEntityId, database).reason ?? null
}

// E15, X10 — rows carrying an entity_id other than this client's mean the filter was bypassed.
export function flagRows(rows, entityId) {
  return rows.some((row) => row.entity_id !== undefined && row.entity_id !== null && String(row.entity_id) !== String(entityId))
}

function parse(sql) {
  let ast
  try {
    ast = parser.astify(String(sql), OPTIONS)
  } catch {
    // Not plain MySQL the parser understands: refuse rather than guess (fail closed).
    refuse("unreadable")
  }
  // E16 — exactly one statement, and it is a SELECT (WITH … SELECT parses as a select).
  if (Array.isArray(ast)) {
    if (ast.length !== 1) refuse("SELECT only")
    ast = ast[0]
  }
  if (ast?.type !== "select") refuse("SELECT only")
  return ast
}

function checkTree(ast, entityId, scoped, database) {
  const ctx = { entityId, scoped, database }
  // E16 — no variables anywhere (v2 tenant views will depend on a session variable).
  walk(ast, (node) => {
    if (node.type === "var") refuse("SELECT only")
    if (node.type === "function" && DENIED_FUNCTIONS.has(functionName(node))) refuse("SELECT only")
  })
  checkSelect(ast, ctx, [], new Set())
}

// Checks one SELECT (and the UNION arms chained after it through _next).
//
// @param outer   anchored aliases of the enclosing SELECTs, for correlated subqueries
// @param ctes    names of CTEs already checked, which count as anchored tables
function checkSelect(select, ctx, outer, ctes) {
  if (select?.type !== "select") refuse("SELECT only")
  const cteNames = new Set(ctes)
  for (const cte of select.with || []) {
    checkSelect(unwrap(cte.stmt), ctx, [], cteNames)
    cteNames.add(ident(cte.name))
  }

  for (let arm = select; arm; arm = arm._next) {
    if (arm.type !== "select") refuse("SELECT only")
    // E16 — INTO OUTFILE/DUMPFILE/@var, and locking reads (FOR UPDATE, FOR SHARE, LOCK IN SHARE MODE).
    if (arm.into?.position || arm.into?.expr) refuse("SELECT only")
    if (arm.locking_read) refuse("SELECT only")
    checkArm(arm, ctx, outer, cteNames)
  }
}

function checkArm(arm, ctx, outer, ctes) {
  const items = (arm.from || []).map((item) => describeItem(item, ctx, outer, ctes))
  const aliases = new Map(items.map((item) => [item.alias, item]))

  // Conditions that restrict every row of this SELECT: the WHERE, and the ON of inner joins.
  const shared = conjuncts(arm.where)
  for (const item of items) {
    // A RIGHT/FULL join keeps rows of the other side whatever the ON says: write it as a LEFT JOIN.
    if (/^(RIGHT|FULL)/i.test(item.join || "")) refuse("add filter")
    if (!item.join || item.join === "INNER JOIN" || item.join === "JOIN") shared.push(...conjuncts(item.on))
  }

  // E14 — any entity_id compared with a literal must be this client's, wherever it appears.
  walk(arm, (node) => {
    if (node.type !== "binary_expr") return
    for (const [column, other] of [[node.left, node.right], [node.right, node.left]]) {
      if (!isColumn(column, "entity_id")) continue
      const values = literals(other)
      if (values && values.some((v) => v !== ctx.entityId)) refuse("other client")
    }
  })

  // Anchor tables until nothing changes: a link only counts once its target is anchored.
  const anchored = new Set(outer)
  for (const item of items) if (item.kind === "trusted") anchored.add(item.alias)
  let changed = true
  while (changed) {
    changed = false
    for (const item of items) {
      if (anchored.has(item.alias)) continue
      const own = item.join && item.join.startsWith("LEFT") ? [...shared, ...conjuncts(item.on)] : shared
      if (own.some((c) => anchors(c, item, items, aliases, anchored, ctx, outer))) {
        anchored.add(item.alias)
        changed = true
      }
    }
  }
  // E13, X18 — every table in this SELECT must be tied to the client.
  if (items.some((item) => !anchored.has(item.alias))) refuse("add filter")

  // Subqueries in the select list, WHERE, HAVING, ON, GROUP BY and ORDER BY are checked as SELECTs of
  // their own, seeing this SELECT's anchored tables (correlated subqueries).
  const visible = [...anchored].filter((alias) => aliases.has(alias) || outer.includes(alias))
  const expressions = [arm.columns, arm.where, arm.having, arm.groupby, arm.orderby, ...items.map((i) => i.on)]
  for (const expression of expressions) forEachSubquery(expression, (sub) => checkSelect(sub, ctx, visible, ctes))
}

// @returns {{alias, table, kind: "scoped"|"entities"|"other"|"trusted", join, on}}
function describeItem(item, ctx, outer, ctes) {
  // A derived table: checked on its own, then trusted like a CTE.
  if (item.expr?.ast || item.expr?.type === "select") {
    checkSelect(unwrap(item.expr), ctx, [], ctes)
    if (!item.as) refuse("unreadable")
    return { alias: ident(item.as), kind: "trusted", join: item.join, on: item.on }
  }
  if (!item.table) refuse("unreadable")
  const table = ident(item.table)
  // X19 — only this database: no information_schema, mysql, performance_schema, sys or other schemas.
  if (item.db && (!ctx.database || ident(item.db) !== ident(ctx.database))) refuse("table not allowed")
  if (DENIED_TABLES.has(table)) refuse("table not allowed")

  const alias = item.as ? ident(item.as) : table
  let kind = "other"
  if (!item.db && ctes.has(table)) kind = "trusted"
  else if (table === "entities") kind = "entities"
  else if (ctx.scoped.has(table)) kind = "scoped"
  return { alias, table, kind, join: item.join, on: item.on }
}

// Does one top-level condition tie `item` to the client?
function anchors(condition, item, items, aliases, anchored, ctx, outer) {
  if (condition.type !== "binary_expr") return false
  const { operator, left, right } = condition
  const mine = (ref) => ref?.type === "column_ref" && refersTo(ref, item, items)

  if (operator === "=") {
    for (const [a, b] of [[left, right], [right, left]]) {
      if (!mine(a)) continue
      const column = ident(a.column)
      // A literal: entity_id for scoped tables, id for entities.
      const values = literals(b)
      if (values?.length === 1 && values[0] === ctx.entityId) {
        if (item.kind === "scoped" && column === "entity_id") return true
        if (item.kind === "entities" && column === "id") return true
      }
      // A join to an anchored table (another table in this SELECT, or an enclosing one).
      if (b?.type === "column_ref" && b.table) {
        const target = ident(b.table)
        if (target === item.alias || !anchored.has(target)) continue
        if (!aliases.has(target) && !outer.includes(target)) continue
        // entities may only be reached through an *entity_id column (investor_entity_id, …).
        if (item.kind === "entities") {
          if (column === "id" && ident(b.column).endsWith("entity_id")) return true
          continue
        }
        if (item.kind === "other") return true
      }
    }
  }
  // <alias>.entity_id IN (<client>) — a one-value list is the same as =.
  if (operator === "IN" && mine(left)) {
    const values = literals(right)
    const column = ident(left.column)
    if (values?.length === 1 && values[0] === ctx.entityId) {
      if (item.kind === "scoped" && column === "entity_id") return true
      if (item.kind === "entities" && column === "id") return true
    }
  }
  // <alias>.<col> IN (SELECT …): the subquery is checked separately; it must read an anchored table.
  if (operator === "IN" && item.kind === "other" && mine(left)) {
    const sub = right?.type === "expr_list" && right.value?.length === 1 ? unwrap(right.value[0]) : null
    if (sub?.type === "select" && (sub.from || []).length > 0) return true
  }
  return false
}

// A column belongs to `item` when qualified with its alias, or unqualified and it is the only table.
function refersTo(ref, item, items) {
  if (ref.table) return ident(ref.table) === item.alias
  return items.length === 1
}

// Splits a condition into its top-level AND parts. An OR at the top is one part, so it anchors nothing.
function conjuncts(expression) {
  if (!expression) return []
  if (expression.type === "binary_expr" && expression.operator === "AND") return [...conjuncts(expression.left), ...conjuncts(expression.right)]
  return [expression]
}

// @returns the literal values (as strings) of a number/string or a list of them, or null when not literal
function literals(node) {
  if (!node) return null
  if (node.type === "number" || node.type === "single_quote_string" || node.type === "double_quote_string" || node.type === "string") return [String(node.value)]
  if (node.type === "expr_list" && Array.isArray(node.value)) {
    const values = node.value.map(literals)
    return values.every(Boolean) ? values.flat() : null
  }
  return null
}

const isColumn = (node, name) => node?.type === "column_ref" && ident(node.column) === name

// Identifiers come as plain strings, or as {type: "backticks_quote_string", value} once quoted (and the
// rebuilt SQL quotes every one), or {expr: {value}} for some columns. @returns the lowercased name, or ""
function ident(value) {
  if (value === null || value === undefined) return ""
  if (typeof value === "object") return ident(value.expr ? value.expr.value : value.value)
  return String(value).toLowerCase()
}

// Subquery nodes come wrapped as {tableList, columnList, ast}.
const unwrap = (node) => (node?.ast ? node.ast : node)

function functionName(node) {
  const name = node.name?.name ? node.name.name.map((part) => part.value).join(".") : node.name
  return String(name ?? "").toLowerCase()
}

// Visits every object in the tree (subqueries included).
function walk(node, visit) {
  if (!node || typeof node !== "object") return
  if (Array.isArray(node)) return node.forEach((child) => walk(child, visit))
  visit(node)
  for (const value of Object.values(node)) walk(value, visit)
}

// Calls back with each SELECT nested in an expression, without descending into it.
function forEachSubquery(node, callback) {
  if (!node || typeof node !== "object") return
  if (Array.isArray(node)) return node.forEach((child) => forEachSubquery(child, callback))
  if (node.ast?.type === "select") return callback(node.ast)
  if (node.type === "select") return callback(node)
  for (const value of Object.values(node)) forEachSubquery(value, callback)
}
