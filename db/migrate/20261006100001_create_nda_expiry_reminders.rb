# frozen_string_literal: true

# Creates the nda_expiry_reminders table for expiry alert idempotency.
# Why: Module 8 daily expiry scanner sends approaching (7-day) and expired alerts.
#   Without a dedup guard, re-running the cron job would send duplicate emails.
#   This table records one row per [nda_config, investor, expiry_date, kind],
#   following the ObligationReminder pattern from side_letters.
#   The unique composite index is the idempotency key — the scanner checks
#   exists? before sending, and RecordNotUnique on race is silently rescued.
#
# @see NdaExpiryReminder
# @see NdaExpiryCheckJob
# @see ObligationReminder — pattern this follows
class CreateNdaExpiryReminders < ActiveRecord::Migration[8.0]
  def change
    create_table :nda_expiry_reminders do |t|
      # Changed: Add nda_config_id FK — scopes reminder to a specific NDA configuration.
      # Why: Each NDA config has its own expiry rules; alerts are tracked per config.
      t.bigint :nda_config_id, null: false

      # Changed: Add investor_id FK — tracks which investor this alert was sent for.
      # Why: Expiry is per-investor (each acceptance has its own expiry date for fixed_period).
      t.bigint :investor_id, null: false

      # Changed: Add expiry_date — the computed expiry date this alert relates to.
      # Why: Enables dedup across cron runs. Same investor with different expiry (after
      #   re-accept) gets a fresh alert series under the new date.
      t.date :expiry_date, null: false

      # Changed: Add kind — "approaching" or "expired".
      # Why: Two distinct one-shot alerts per expiry event. Unlike ObligationReminder,
      #   no overdue escalation — GP uses "Send Reminders" for follow-up.
      t.string :kind, limit: 20, null: false

      # Changed: Add sent_at — when the alert was actually sent.
      # Why: Audit trail for support debugging ("when did investor X get alerted?").
      t.datetime :sent_at, null: false

      t.timestamps
    end

    # Changed: Unique composite index for idempotency guard.
    # Why: Scanner checks exists? on this index before sending. RecordNotUnique on
    #   concurrent job race is silently rescued — no duplicate alert possible.
    add_index :nda_expiry_reminders,
              %i[nda_config_id investor_id expiry_date kind],
              unique: true,
              name: "idx_nda_expiry_reminders_dedup"

    # Changed: FK index on nda_config_id.
    # Why: Supports has_many from NdaConfig and scanner's per-config queries.
    add_index :nda_expiry_reminders, :nda_config_id,
              name: "idx_nda_expiry_reminders_config"

    # Changed: FK index on investor_id.
    # Why: Standard FK index for referential integrity lookups.
    add_index :nda_expiry_reminders, :investor_id,
              name: "fk_nda_expiry_reminders_investor"
  end
end
