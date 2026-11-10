# frozen_string_literal: true

# Retention (OWASP review 2026-11 M11, design card ⑧, D9, H35, E43): events that happened more than 13 months ago
# are deleted every night — a full year for the annual review plus a month's margin. The only delete there is.
#
# In batches of 5,000 on the primary key, each batch bounded by the occurred_at index, so a large first run never
# holds one long lock. An event exactly 13 months old is kept; one second older goes (E43).
class SecurityEventPurgeJob < ApplicationJob
  queue_as :low
  BATCH = 5_000

  def perform
    cutoff = SecurityEvent::RETENTION.ago
    # E43 — strictly older than the cut-off
    deleted = 0
    SecurityEvent.where(occurred_at: ...cutoff).in_batches(of: BATCH) { |batch| deleted += batch.delete_all }
    Rails.logger.info("[security_event] purged #{deleted} events older than #{cutoff.iso8601}")
  end
end
