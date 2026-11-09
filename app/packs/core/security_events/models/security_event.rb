# frozen_string_literal: true

# One append-only row per security-relevant moment (OWASP review 2026-11 M11, design card ⑤).
#
# Written only by SecurityEvents.record → SecurityEventWriteJob (or the inline fallback), read by the Security
# Events screen, the download and the weekly pack, and deleted only by SecurityEventPurgeJob after 13 months.
# Corrections are new rows (a revoke after a grant), never edits.
#
# Deliberately not Trackable (an audit of the audit), not paranoid and not indexed in Elasticsearch.
class SecurityEvent < ApplicationRecord
  # Never replicated, never soft-deleted: plain belongs_to, all optional (a failure may have no account)
  belongs_to :entity, optional: true
  belongs_to :user, optional: true
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :impersonator, class_name: "User", optional: true

  # The columns the screen, the download and the weekly pack read — everything except the digest
  STANDARD_COLUMNS = %w[id entity_id kind category outcome door user_id actor_id impersonator_id ip_address
                        user_agent request_id region details occurred_at].freeze

  # Retention (D9): 13 months, a full year plus a month for the year-on-year comparison
  RETENTION = 13.months

  scope :for_period, ->(range) { where(occurred_at: range) }
  scope :failures, -> { where(outcome: "failure") }

  # X4 — once saved, a row can't be changed or destroyed through the model
  def readonly?
    persisted?
  end

  # Writes one event from the recorder's attrs hash. Idempotent by uid: a retried job (or a retried inline
  # write) inserts nothing the second time and returns nil, so no second alert is sent (E33).
  #
  # S2a — a website sign-in failure carries the typed email (never stored): resolved here, off the request
  # thread so the Warden hook stays query-free and timing-neutral. When it names an account, the account and
  # its firm are stored and the digest is dropped; when not, only the digest remains (E2).
  #
  # @param attrs [Hash] from SecurityEvents.build
  # @return [SecurityEvent, nil] the new row, or nil when the uid was already written
  def self.write!(attrs)
    attrs = attrs.to_h.stringify_keys
    # The typed email is used for the lookup only, then dropped
    email = attrs.delete("email")
    if email.present? && attrs["user_id"].blank?
      account = User.find_for_authentication(email:)
      if account
        attrs["user_id"] = account.id
        attrs["entity_id"] ||= account.entity_id
        attrs["identifier_digest"] = nil
        # E3 — Devise is paranoid, so Warden reports a locked account as :invalid (the page must not reveal the
        # lock). The trail is not shown to the person signing in, so it names the real reason.
        attrs["details"] = (attrs["details"] || {}).merge("reason" => "locked") if attrs.dig("details", "reason").to_s == "invalid" && account.access_locked?
      end
    end
    # One insert; the unique uid index is the duplicate check (no read first)
    create!(attrs.slice(*column_names))
  rescue ActiveRecord::RecordNotUnique
    # E33 — an earlier attempt (a Sidekiq retry, or the inline fallback) already wrote this uid
    nil
  end

  # The screen's filters (LLD "Controllers"). Never entity_id (the tenant filter is the policy's alone, X8),
  # never details or identifier_digest (the digest is searched through the email filter, which digests input)
  def self.ransackable_attributes(_auth_object = nil)
    %w[kind category outcome door ip_address occurred_at user_id actor_id region]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  # Plain words for the screen and the spreadsheets
  def label
    SecurityEventCatalogue.label(kind)
  end

  def door_label
    SecurityEventCatalogue.door_label(door)
  end

  def category_label
    SecurityEventCatalogue.category_label(category)
  end

  def failure?
    outcome == "failure"
  end

  # The Event label as the row and its popup show it: with the role for a role change ("Role granted: Approver")
  def display_label
    role = details&.dig("role")
    role.present? ? "#{label}: #{role.to_s.humanize}" : label
  end

  # The row's "What to do" popup parts (SecurityEventCatalogue::ADVICE): normal:, act:
  def advice
    SecurityEventCatalogue.advice(kind, failure: failure?)
  end

  # The details as one short line, e.g. "Role: approver" or "Reason: invalid"
  def details_text
    (details || {}).map { |key, value| "#{key.to_s.humanize}: #{value}" }.join(" · ")
  end
end
