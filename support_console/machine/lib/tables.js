// The tables that carry an entity_id column, generated from db/schema.rb into the code archive by
// `rake support_console:publish_code` (or local_setup), so the rules follow the deployed schema.
import fs from "node:fs"
import path from "node:path"

export function tablesWithEntityId(codeDir = process.env.SUPPORT_CONSOLE_CODE_DIR) {
  try {
    const file = path.join(codeDir, "tables_with_entity_id.json")
    return new Set(JSON.parse(fs.readFileSync(file, "utf8")))
  } catch {
    // Without the list no table counts as scoped, so nothing can anchor a lookup (apart from the
    // client's own entities row): lookups are refused until the list is deployed.
    return new Set()
  }
}

// X19 — tables the console never reads, whatever the conditions: credentials and tokens, admin and
// mailbox internals, and logs that hold every client's history without an entity_id to filter on.
export const DENIED_TABLES = new Set([
  "api_tokens", "devise_api_tokens", "oauth_access_grants", "oauth_applications", "oauth_openid_requests",
  "otp_deliveries", "mobile_devices", "mobile_push_deliveries", "admin_users", "active_admin_comments",
  "action_mailbox_inbound_emails", "agent_ingested_emails", "solid_cache_entries", "exception_tracks",
  "blazer_audits", "blazer_checks", "blazer_dashboard_queries", "blazer_dashboards", "blazer_queries",
  "audits", "versions", "website_leads",
])
