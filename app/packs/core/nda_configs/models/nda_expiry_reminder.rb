# frozen_string_literal: true

# @description Idempotency guard for NDA expiry alerts. Records one row per
#   [nda_config, investor, expiry_date, kind] to prevent the daily cron job
#   (NdaExpiryCheckJob) from sending duplicate approaching/expired emails.
#   Follows the ObligationReminder pattern from side_letters.
#
# Changed: Module 8 — new model for expiry alert dedup.
# Why: The daily expiry scanner runs every day. Without a dedup guard, it would
#   re-send the same 7-day warning or expired alert on every subsequent run.
#   The unique composite index enforces at-most-once delivery per alert kind.
#   RecordNotUnique on concurrent job race is silently rescued by the scanner.
#
# @see NdaExpiryCheckJob — the daily scanner that creates these records
# @see ObligationReminder — pattern this follows
# @see NdaConfig
class NdaExpiryReminder < ApplicationRecord
  KINDS = %w[approaching expired].freeze

  belongs_to :nda_config
  belongs_to :investor

  validates :kind, presence: true, inclusion: { in: KINDS }

  # Changed: Uniqueness validation matching the DB unique index.
  # Why: One alert per investor per expiry date per kind. Both kinds are one-shot
  #   (no overdue escalation like ObligationReminder) — GP uses "Send Reminders"
  #   for manual follow-up instead.
  validates :kind, uniqueness: { scope: %i[nda_config_id investor_id expiry_date] }

  # @param nda_config_id [Integer] the NDA config to check
  # @param investor_id [Integer] the investor to check
  # @param expiry_date [Date] the computed expiry date
  # @param kind [String] "approaching" or "expired"
  # @return [Boolean] true if this alert was already sent
  def self.already_sent?(nda_config_id, investor_id, expiry_date, kind)
    exists?(nda_config_id: nda_config_id, investor_id: investor_id,
            expiry_date: expiry_date, kind: kind)
  end
end
