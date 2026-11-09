# frozen_string_literal: true

# Writes one security event off the request thread (OWASP review 2026-11 M11, design card ④).
#
# The attrs were built by SecurityEvents.record on the request (IP, user agent, actor, firm, uid, time); this
# job only inserts them and, for a fresh row only, asks SecurityEventAlert whether the firm's admins must be
# told (role / support changes, D8). A retry finds the uid already written and does nothing — no second row,
# no second alert (E33).
#
# :default, not :low — :low holds the long dumps, and a security alert half an hour late is not useful.
class SecurityEventWriteJob < ApplicationJob
  queue_as :default
  # The attrs carry an IP, a user agent and (for a website failure) the typed email: never in the Sidekiq log
  self.log_arguments = false

  # The actor is already in the attrs (read on the request thread), and security_events is not audited, so
  # ApplicationJob's acting-user lookup (one users query per job) is not needed here
  def acting_user
    nil
  end

  # @param attrs [Hash] from SecurityEvents.build
  def perform(attrs)
    # H28 / E33 — insert once by uid; nil when an earlier attempt already wrote it
    event = SecurityEvent.write!(attrs)
    return if event.nil?

    # ⑦ — only a fresh insert may alert
    SecurityEventAlert.deliver(event)
  end
end
