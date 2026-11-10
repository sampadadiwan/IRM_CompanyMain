# OWASP review 2026-11 M11 (openspec/changes/archive/2026-11-10-security-event-trail, design card ⑤, LLD "Schema Detail").
#
# The append-only security event trail: one row per sign-in, two-factor, account, role, support-access,
# credential or export moment. A new, empty table — no backfill, nothing else changes.
#
# No foreign keys on purpose: a deleted user or firm must neither block nor cascade-delete the evidence.
# No updated_at: rows are written once (SecurityEvent#readonly?) and only the retention purge deletes them.
class CreateSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :security_events do |t|
      # Idempotent write: a retried SecurityEventWriteJob inserts nothing the second time (E33)
      t.string :uid, limit: 36, null: false
      # Tenant scope; NULL = an unknown account (CapHive super users only, D7)
      t.bigint :entity_id
      t.string :kind, limit: 40, null: false
      t.string :category, limit: 20, null: false
      t.string :outcome, limit: 10, null: false, default: "success"
      t.string :door, limit: 20, null: false
      # Account the event is about / who did it / CapHive support behind an impersonated session
      t.bigint :user_id
      t.bigint :actor_id
      t.bigint :impersonator_id
      # HMAC of the typed email on a failed sign-in with no matching account — never the email (D10)
      t.string :identifier_digest, limit: 64
      t.string :ip_address, limit: 45
      t.string :user_agent, limit: 255
      t.string :request_id, limit: 36
      t.string :region, limit: 5, null: false
      # Allowlisted keys only (SecurityEventCatalogue), never a secret
      t.json :details
      # When it happened (on the request thread); created_at is when the job wrote it
      t.datetime :occurred_at, precision: 6, null: false
      t.datetime :created_at, precision: 6, null: false

      t.index :uid, unique: true
      t.index %i[entity_id occurred_at]
      t.index %i[user_id occurred_at]
      t.index %i[kind occurred_at]
      t.index %i[ip_address occurred_at]
      t.index :occurred_at
    end
  end
end
