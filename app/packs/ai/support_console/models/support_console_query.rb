# frozen_string_literal: true

# One lookup the Support Console's assistant attempted, recorded from the relay's `query` events
# by SupportConsoleTurnJob. Append-only: the audit trail of who read what, about which client.
# Holds the statement and counts, never the rows themselves.
#
# @see openspec/changes/archive/2026-10-22-support-console/design.md (card ⑧ Query record and alerts)
class SupportConsoleQuery < ApplicationRecord
  OUTCOMES = %w[ran blocked failed].freeze

  belongs_to :user
  belongs_to :entity
  belongs_to :agent_chat_session, optional: true
  belongs_to :agent_chat_message, optional: true

  validates :outcome, inclusion: { in: OUTCOMES }
  validates :sql_text, :code_rev, :event_seq, presence: true
  validates :reason, length: { maximum: 255 }
  validates :code_rev, length: { maximum: 40 }

  scope :flagged, -> { where(flagged: true) }

  # E15, X10 — a lookup that returned another client's rows alerts super users, once per row (X14).
  after_create_commit :notify_flagged, if: :flagged?

  # Records one `query` event; a re-read of the same event is a no-op (X14).
  #
  # @param event [Hash] the relay's query event (seq, sql, outcome, reason, row_count, duration_ms, lag_seconds, flagged)
  # @param message [AgentChatMessage] the assistant message of the turn
  # @param code_rev [String, nil] the code version the turn ran on, when known
  # @param user [User, nil] who asked the turn (X23); the conversation's starter when not given
  # @return [SupportConsoleQuery, nil] nil when the event was already recorded
  def self.record_event!(event, message:, code_rev: nil, user: nil)
    session = message.agent_chat_session
    create!(
      user_id: user&.id || session.analyst_id,
      entity_id: session.chattable_id,
      agent_chat_session: session,
      agent_chat_message: message,
      event_seq: event["seq"].to_i,
      sql_text: event["sql"].presence || "(no statement)",
      # An outcome the record does not know is kept as a failure rather than lost.
      outcome: OUTCOMES.include?(event["outcome"]) ? event["outcome"] : "failed",
      # E13, E14, E16, E19 — why it was blocked or failed, kept short.
      reason: event["reason"].to_s.truncate(255).presence,
      flagged: event["flagged"] == true,
      row_count: event["row_count"],
      duration_ms: event["duration_ms"],
      lag_seconds: event["lag_seconds"],
      code_rev: (event["code_rev"] || code_rev).presence || "unknown"
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Rows are written once and never changed.
  def readonly?
    persisted?
  end

  private

  def notify_flagged
    SupportConsoleQueryFlaggedNotifier.with(record: self, entity_id: entity_id)
                                      .deliver(User.with_role(:super).to_a)
  end
end
