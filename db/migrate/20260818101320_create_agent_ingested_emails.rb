# frozen_string_literal: true

# Audit log of every email that passed authentication in the Deal Update
# Agent pipeline.
#
# Every email that arrives at a valid, non-revoked DealIngestAddress and
# passes sender + SPF/DKIM/DMARC verification gets a row here. Emails
# that fail auth are dropped silently (FR-4) and never recorded.
#
# The row tracks the full lifecycle: pending → filed (note/task created)
# or warehoused (couldn't match confidently). The raw_payload is kept so
# we can re-process if the LLM misparses, and parse_json stores the
# structured output for debugging and analytics.
class CreateAgentIngestedEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_ingested_emails do |t|
      t.references :deal, null: false, foreign_key: true
      t.references :sender_user, null: false, foreign_key: { to_table: :users }

      # RFC-822 Message-ID header from the original email.
      # Unique index enforces dedupe — if SendGrid redelivers the same
      # email (e.g. webhook timeout), we skip it silently (FR-15).
      t.string :message_id, null: false

      # Original email content from SendGrid's parsed payload.
      # Kept for debugging (re-process if LLM misparses) and audit.
      t.text :raw_payload

      # When SendGrid received the email, not when we processed it.
      t.datetime :received_at, null: false

      # State machine: pending → filed | warehoused | dropped.
      # 'pending' = enqueued for processing, 'filed' = note/task created,
      # 'warehoused' = couldn't match confidently, 'dropped' = parse failure.
      t.string :status, null: false, default: "pending", limit: 20

      # LLM structured output: { intent, stakeholder_string, body, due_date }.
      # Stored alongside the email for debugging and threshold tuning.
      t.json :parse_json

      # Stakeholder match confidence score (0.00–1.00).
      # Used for analytics and tuning the auto-file threshold.
      t.decimal :confidence, precision: 5, scale: 2

      # Which matching tier was used: A (deal-scoped exact/fuzzy),
      # B/C/D/E reserved for Phase 2+. Stored now to avoid a migration later.
      t.string :match_tier, limit: 2

      t.timestamps
    end

    # Dedupe index — one row per unique email across the system.
    add_index :agent_ingested_emails, :message_id, unique: true

    # Filter by processing status (e.g. "show all pending").
    add_index :agent_ingested_emails, :status
  end
end

