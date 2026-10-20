#!/usr/bin/env node
// The Support Console's data tool (design card ⑦): a stdio MCP server Claude Code starts from the
// per-turn mcp.json. Its tools are the only way Claude reaches client data.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js"
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js"
import { z } from "zod"
import { runLookup, describeTables, ROW_CAP } from "../lib/db.js"
import { appendError } from "../lib/events.js"

const entityId = process.env.SUPPORT_ENTITY_ID
const server = new McpServer({ name: "db", version: "1.0.0" })

const json = (data) => ({ content: [{ type: "text", text: JSON.stringify(data) }] })
const failure = (error) => {
  // X11, X12 — no replica, or not a read-only one: the whole turn fails, not just this lookup.
  if (error.code === "not_a_replica" || error.code === "db_unavailable") appendError(error.code, error.message)
  return { content: [{ type: "text", text: error.message }], isError: true }
}

server.registerTool(
  "query",
  {
    description:
      `Run ONE read-only MySQL SELECT on the production read replica for client entity_id ${entityId}. ` +
      `Every table with an entity_id column must be filtered with entity_id = ${entityId}. ` +
      `At most ${ROW_CAP} rows come back, with total_rows; aggregate in SQL (SUM, COUNT, GROUP BY) instead of pulling rows. ` +
      "Statements are cancelled after 30 seconds: filter on indexed columns.",
    inputSchema: { sql: z.string().describe("A single SELECT or WITH … SELECT statement") },
  },
  async ({ sql }) => {
    try {
      return json(await runLookup(sql, entityId))
    } catch (error) {
      return failure(error)
    }
  }
)

server.registerTool(
  "describe_tables",
  {
    description: "Columns of the named tables (exactly production's schema), to write correct SQL.",
    inputSchema: { names: z.array(z.string()).min(1).max(20) },
  },
  async ({ names }) => {
    try {
      return json(await describeTables(names))
    } catch (error) {
      return failure(error)
    }
  }
)

await server.connect(new StdioServerTransport())
