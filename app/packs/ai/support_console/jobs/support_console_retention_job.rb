# frozen_string_literal: true

# Daily Support Console housekeeping (design card ⑧):
#   1. conversations whose last message is more than 90 days old are deleted — their Claude Code
#      transcripts on the support machine first, then the rows; their query records stay (the
#      foreign keys are nullified by the database);
#   2. turns left queued or running for more than 20 minutes (a Sidekiq restart mid-turn) are
#      closed so their conversation can be used again.
#
# @see openspec/changes/archive/2026-10-22-support-console/design.md (card ⑧ Query record and alerts)
class SupportConsoleRetentionJob < ApplicationJob
  queue_as :low

  RETENTION = 90.days
  STALE_TURN = 20.minutes
  INTERRUPTED = "The answer was interrupted. Please ask again."
  SWEEP_WINDOW = 3.days
  # A relay down or gone (machine decommissioned) must not keep client conversations forever.
  TRANSCRIPT_GRACE = 7.days

  # X26 — a running turn is stale STALE_TURN after the job started it, not after it was queued: time
  # waiting for a free capsule thread is not time Claude spent. A turn never started counts from
  # when it was queued.
  #
  # @param message [AgentChatMessage] an assistant message whose turn is queued or running
  # @return [Boolean]
  def self.stale_turn?(message, now: Time.current)
    started = message.metadata&.dig("started_at")
    from = started.present? ? Time.zone.parse(started) : message.created_at
    from < now - STALE_TURN
  end

  def perform
    agent = SupportConsoleAgent.existing
    return unless agent

    close_stale_turns(agent)
    purge_old_conversations(agent)
  end

  private

  # E20 — a conversation last active more than 90 days ago is removed; one at exactly 90 days stays.
  def purge_old_conversations(agent)
    relay = SupportConsoleRelayClient.new
    # By date, not to the second: 90 days ago is kept all day, 91 days ago is gone.
    AgentChatSession.where(support_agent: agent).where(updated_at: ...RETENTION.ago.beginning_of_day).find_each do |session|
      # The machine's transcripts go first: if the relay is down, keep the conversation for tomorrow.
      claude_session_ids(session).each { |id| relay.delete_transcript(session.chattable_id, id) }
      # Query records outlive the conversation. The FKs are ON DELETE SET NULL in MySQL; doing it
      # here as well keeps the result the same on databases that do not enforce foreign keys.
      SupportConsoleQuery.where(agent_chat_session_id: session.id).update_all(agent_chat_session_id: nil, agent_chat_message_id: nil)
      session.destroy!
    rescue SupportConsoleRelayClient::Error => e
      # Kept for tomorrow while the relay may come back; past the grace period the rows go anyway
      # and the transcripts left on the machine are reported for manual removal.
      if session.updated_at < (RETENTION + TRANSCRIPT_GRACE).ago
        left_on_machine = claude_session_ids(session)
        SupportConsoleQuery.where(agent_chat_session_id: session.id).update_all(agent_chat_session_id: nil, agent_chat_message_id: nil)
        session.destroy!
        ErrorReport.notify(e, job: self, purged_without_transcripts: session.id, claude_session_ids: left_on_machine)
      else
        Rails.logger.warn("[support_console] retention kept session=#{session.id}: #{e.class}: #{e.message}")
      end
    end
  end

  # Turns a restart left behind would otherwise block their conversation forever (E4's guard).
  def close_stale_turns(agent)
    AgentChatMessage.joins(:agent_chat_session)
                    .where(agent_chat_sessions: { support_agent_id: agent.id }, role: "assistant")
                    # Only recent turns can still be open; older ones were closed by earlier sweeps.
                    .where(created_at: SWEEP_WINDOW.ago...STALE_TURN.ago)
                    .find_each do |message|
      next unless %w[queued running].include?(message.metadata&.dig("turn_status"))
      next unless self.class.stale_turn?(message)

      message.update!(content: INTERRUPTED, metadata: message.metadata.merge("turn_status" => "failed"))
    end
  end

  # @return [Array<String>] every Claude Code session id the conversation's turns used
  def claude_session_ids(session)
    session.agent_chat_messages.where(role: "assistant").filter_map { |m| m.metadata&.dig("claude_session_id") }.uniq
  end
end
