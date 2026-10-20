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
//   - any other table:         a REAL LINK to an anchored table, from join_map.json (tenant-scope ③):
//                              <alias>.<fk> = <parent>.id, or <alias>.id = <child>.<fk>, a polymorphic
//                              <alias>.<name>_id = <parent>.id with <alias>.<name>_type = '<Class>', or
//                              <alias>.<fk> IN (SELECT <parent>.id …) along the same link
// A table without entity_id that has no link at all is "table not allowed"; one that has links but
// is not tied by one is refused naming the links it could use. Secret and cross-client tables
// (DENIED_TABLES) are refused whatever the conditions.
//
// After the checks, addScopeColumns adds a hidden __scope_<alias> column per scoped table of the outer
// SELECT (tenant-scope ⑤), and heldBack lets the data tool refuse a result that holds another
// client's row (⑦) — a net under the SQL checks, in case they ever miss a trick.
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

const NO_LINKS = { links: {}, classes: {} }
const SCOPE_PREFIX = "__scope_"

// @param joinMap {{links, classes}} from join_map.json (tables.loadJoinMap); without it no table
//   lacking entity_id can be tied (X8, fail closed)
// @returns {{sql: string, scopeColumns: string[]}} the statement to execute and the hidden columns it
//   carries, or {{reason: string}} why it is refused
export function prepareStatement(sql, entityId, tablesWithEntityId, database = null, joinMap = NO_LINKS) {
  try {
    // Check the statement Claude sent, rebuild it, then check the rebuilt text too: a rebuild that
    // dropped a condition would be refused rather than run unscoped.
    const ast = parse(sql)
    checkTree(ast, String(entityId), tablesWithEntityId, database, joinMap)
    const rebuilt = parser.sqlify(ast, OPTIONS)
    const checked = parse(rebuilt)
    checkTree(checked, String(entityId), tablesWithEntityId, database, joinMap)
    // ⑤ — the hidden scope columns go on the checked tree, after both checks (they use the reserved prefix)
    const scopeColumns = addScopeColumns(checked, tablesWithEntityId)
    return { sql: scopeColumns.length ? parser.sqlify(checked, OPTIONS) : rebuilt, scopeColumns }
  } catch (error) {
    if (error instanceof Refusal) return { reason: error.message }
    throw error
  }
}

// @returns {string|null} why the statement is refused, or null when it may run
export function checkStatement(sql, entityId, tablesWithEntityId, database = null, joinMap = NO_LINKS) {
  return prepareStatement(sql, entityId, tablesWithEntityId, database, joinMap).reason ?? null
}

// ⑦ X11 — a row whose hidden scope column names another client means the checks were bypassed.
// NULL is skipped: a LEFT JOIN miss, a padded UNION arm, or MIN/MAX over no rows (E4, E12, E13).
export function heldBack(rows, entityId) {
  return rows.some((row) => Object.entries(row).some(([key, value]) =>
    key.startsWith(SCOPE_PREFIX) && value !== null && value !== undefined && String(value) !== String(entityId)))
}

// The rows and column names as Claude asked for them: the hidden scope columns removed (H1).
export function withoutScope(rows, columns) {
  const visible = columns.filter((name) => !name.startsWith(SCOPE_PREFIX))
  return {
    columns: visible,
    rows: rows.map((row) => Object.fromEntries(Object.entries(row).filter(([key]) => !key.startsWith(SCOPE_PREFIX)))),
  }
}

// E7, X1 — the links a table without entity_id can be tied by, for the refusal Claude reads: its own
// foreign keys first, then the tables that point at it. At most 3, in schema order.
export function linksFor(table, joinMap = NO_LINKS) {
  const usable = []
  for (const link of joinMap.links[table] || []) {
    usable.push(link.to
      ? `${table}.${link.column} = ${link.to}.id`
      : `${table}.${link.polymorphic} = '<Class>' AND ${table}.${link.column} = <that table>.id`)
  }
  for (const [child, list] of Object.entries(joinMap.links)) {
    for (const link of list) if (link.to === table) usable.push(`${table}.id = ${child}.${link.column}`)
  }
  return usable.slice(0, 3)
}

// ⑤ — adds the outer SELECT's hidden scope columns: per table with entity_id, its own entity_id
// (never an *_entity_id column, §4), as __scope_<alias>, or __scope_<alias>_min/_max when the SELECT
// groups or aggregates (valid under ONLY_FULL_GROUP_BY). UNION arms share positional columns (below).
// CTEs and derived tables add none: they were checked on their own.
//
// @returns {string[]} the hidden column names added
// @throws Refusal("unreadable") for a shape the rewrite cannot extend safely (X10)
export function addScopeColumns(ast, scoped) {
  const arms = []
  for (let arm = ast; arm; arm = arm._next) {
    // X10 — INTERSECT / EXCEPT compare whole rows; extra columns would change what they compare.
    // set_op on an arm names how it joins the next one.
    if (arm._next && !/^union/i.test(String(arm.set_op || ""))) refuse("unreadable")
    if (!Array.isArray(arm.columns)) refuse("unreadable")
    arms.push(arm)
  }
  const cteNames = new Set((ast.with || []).map((cte) => ident(cte.name)))

  const perArm = arms.map((arm) => {
    const aliases = (arm.from || [])
      .filter((item) => item.table && !item.expr && scoped.has(ident(item.table)) && (item.db || !cteNames.has(ident(item.table))))
      .map((item) => ident(item.as || item.table))
    const grouped = Boolean(arm.groupby) || arm.columns.some((column) => aggregates(column.expr))
    const column = (alias) => ({ type: "column_ref", table: alias, column: "entity_id" })
    return grouped
      ? aliases.flatMap((alias) => [
        [`${alias}_min`, { type: "aggr_func", name: "MIN", args: { expr: column(alias) }, over: null }],
        [`${alias}_max`, { type: "aggr_func", name: "MAX", args: { expr: column(alias) }, over: null }],
      ])
      : aliases.map((alias) => [alias, column(alias)])
  })

  // One SELECT: __scope_<alias>. A UNION: positional __scope_1.._n, each arm padded with its own
  // first scope value, so rows the UNION would merge still merge (E4); NULL only for an arm with no
  // table that has entity_id.
  if (arms.length === 1) {
    for (const [name, expr] of perArm[0]) arms[0].columns.push({ expr, as: `${SCOPE_PREFIX}${name}` })
    return perArm[0].map(([name]) => `${SCOPE_PREFIX}${name}`)
  }
  const width = Math.max(...perArm.map((list) => list.length))
  const names = Array.from({ length: width }, (_, index) => `${SCOPE_PREFIX}${index + 1}`)
  arms.forEach((arm, index) => {
    const list = perArm[index]
    names.forEach((name, position) => {
      const expr = list[position]?.[1] ?? list[0]?.[1] ?? { type: "null", value: null }
      arm.columns.push({ expr: structuredClone(expr), as: name })
    })
  })
  return names
}

// Does this select-list expression aggregate (outside window functions and subqueries)?
function aggregates(node) {
  if (!node || typeof node !== "object") return false
  if (Array.isArray(node)) return node.some(aggregates)
  if (node.ast || node.type === "select") return false
  if (node.type === "aggr_func" && !node.over) return true
  return Object.values(node).some(aggregates)
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

function checkTree(ast, entityId, scoped, database, joinMap) {
  const ctx = { entityId, scoped, database, joinMap: joinMap || NO_LINKS }
  // E16 — no variables anywhere (v2 tenant views will depend on a session variable).
  walk(ast, (node) => {
    if (node.type === "var") refuse("SELECT only")
    if (node.type === "function" && DENIED_FUNCTIONS.has(functionName(node))) refuse("SELECT only")
    // tenant-scope X9 — the hidden scope columns' prefix is reserved, so Claude cannot fake one
    if (ident(node.as).startsWith(SCOPE_PREFIX) || (node.type === "column_ref" && ident(node.column).startsWith(SCOPE_PREFIX))) refuse("unreadable")
  })
  checkSelect(ast, ctx, new Map(), new Set())
}

// Checks one SELECT (and the UNION arms chained after it through _next).
//
// @param outer   anchored aliases of the enclosing SELECTs → their table (null for a CTE or derived
//                table), for correlated subqueries
// @param ctes    names of CTEs already checked, which count as anchored tables
function checkSelect(select, ctx, outer, ctes) {
  if (select?.type !== "select") refuse("SELECT only")
  const cteNames = new Set(ctes)
  for (const cte of select.with || []) {
    checkSelect(unwrap(cte.stmt), ctx, new Map(), cteNames)
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
  const anchored = new Set(outer.keys())
  for (const item of items) if (item.kind === "trusted") anchored.add(item.alias)
  let changed = true
  while (changed) {
    changed = false
    for (const item of items) {
      if (anchored.has(item.alias)) continue
      const own = item.join && item.join.startsWith("LEFT") ? [...shared, ...conjuncts(item.on)] : shared
      if (own.some((c) => anchors(c, item, items, aliases, anchored, ctx, outer, own))) {
        anchored.add(item.alias)
        changed = true
      }
    }
  }
  // E13, X18 — every table in this SELECT must be tied to the client. A table with entity_id (or
  // entities) that is not is the usual mistake, so it is reported first.
  const loose = items.filter((item) => !anchored.has(item.alias))
  if (loose.some((item) => item.kind !== "other")) refuse("add filter")
  if (loose.length) {
    // tenant-scope X4 / E7, X1 — no link at all, or links that were not used (named for Claude)
    const usable = linksFor(loose[0].table, ctx.joinMap)
    if (usable.length === 0) refuse("table not allowed")
    refuse(`join on a real relationship: ${loose[0].table} can be joined by ${usable.join(", ")}`)
  }

  // Subqueries in the select list, WHERE, HAVING, ON, GROUP BY and ORDER BY are checked as SELECTs of
  // their own, seeing this SELECT's anchored tables (correlated subqueries) and what each one is.
  const visible = new Map()
  for (const alias of anchored) {
    if (aliases.has(alias)) visible.set(alias, aliases.get(alias).table ?? null)
    else if (outer.has(alias)) visible.set(alias, outer.get(alias))
  }
  const expressions = [arm.columns, arm.where, arm.having, arm.groupby, arm.orderby, ...items.map((i) => i.on)]
  for (const expression of expressions) forEachSubquery(expression, (sub) => checkSelect(sub, ctx, visible, ctes))
}

// @returns {{alias, table, kind: "scoped"|"entities"|"other"|"trusted", join, on}}
function describeItem(item, ctx, outer, ctes) {
  // A derived table: checked on its own, then trusted like a CTE.
  if (item.expr?.ast || item.expr?.type === "select") {
    checkSelect(unwrap(item.expr), ctx, new Map(), ctes)
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
//
// @param siblings the other top-level conditions on the same rows, where a polymorphic type is pinned
function anchors(condition, item, items, aliases, anchored, ctx, outer, siblings) {
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
        if (!aliases.has(target) && !outer.has(target)) continue
        // entities may only be reached through an *entity_id column (investor_entity_id, …).
        if (item.kind === "entities") {
          if (column === "id" && ident(b.column).endsWith("entity_id")) return true
          continue
        }
        // tenant-scope ③ — a table without entity_id only along a real link (H1, H2, E1, X1).
        const targetTable = aliases.has(target) ? aliases.get(target).table : outer.get(target)
        if (item.kind === "other" && realLink(item, column, target, targetTable, ident(b.column), siblings, items, ctx)) return true
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
  // <alias>.<fk> IN (SELECT <t>.<col> FROM <t> …): the subquery is checked separately (it must be tied
  // to the client); the column it returns must be the other end of a real link (E2, X2).
  if (operator === "IN" && item.kind === "other" && mine(left)) {
    const sub = right?.type === "expr_list" && right.value?.length === 1 ? unwrap(right.value[0]) : null
    const returned = sub?.type === "select" && !sub._next && sub.columns?.length === 1 ? sub.columns[0].expr : null
    if (returned?.type === "column_ref") {
      const from = (sub.from || []).filter((entry) => entry.table && !entry.expr)
      const source = returned.table
        ? from.find((entry) => ident(entry.as || entry.table) === ident(returned.table))
        : (from.length === 1 && (sub.from || []).length === 1 ? from[0] : null)
      if (source && realLink(item, ident(left.column), ident(source.as || source.table), ident(source.table), ident(returned.column), siblings, items, ctx)) return true
    }
  }
  return false
}

// tenant-scope ③ — is `item.column = target.targetColumn` a real link from join_map.json? Either way
// round: the item's foreign key to the target's id, or the item's id from the target's foreign key.
// A polymorphic link also needs its type pinned, in the same conditions, to the other table's class
// (H3, E8, X3). A CTE or derived table (targetTable null) has no known links.
function realLink(item, column, target, targetTable, targetColumn, siblings, items, ctx) {
  if (!targetTable || !item.table) return false
  const { links, classes } = ctx.joinMap
  if (targetColumn === "id") {
    for (const link of links[item.table] || []) {
      if (link.column !== column) continue
      if (link.to === targetTable) return true
      if (link.polymorphic && pinned(item.alias, link.polymorphic, classes[targetTable], siblings, items)) return true
    }
  }
  if (column === "id") {
    for (const link of links[targetTable] || []) {
      if (link.column !== targetColumn) continue
      if (link.to === item.table) return true
      if (link.polymorphic && pinned(target, link.polymorphic, classes[item.table], siblings, items)) return true
    }
  }
  return false
}

// Is `<alias>.<typeColumn> = '<className>'` one of the conditions? Case-sensitive, as Rails stores it.
function pinned(alias, typeColumn, className, siblings, items) {
  if (!className) return false
  return siblings.some((condition) => {
    if (condition.type !== "binary_expr" || condition.operator !== "=") return false
    return [[condition.left, condition.right], [condition.right, condition.left]].some(([a, b]) => {
      if (a?.type !== "column_ref" || ident(a.column) !== typeColumn) return false
      if (a.table ? ident(a.table) !== alias : items.length !== 1) return false
      const values = literals(b)
      return values?.length === 1 && values[0] === className
    })
  })
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
