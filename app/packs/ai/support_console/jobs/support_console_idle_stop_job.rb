# frozen_string_literal: true

# Stops the support machine when nobody has asked a question for IDLE_MINUTES. The next question
# starts it again (SupportConsoleTurnJob#wake_machine), so stopping only costs that question ~2 minutes.
#
# Runs every 10 minutes from sidekiq-cron. SUPPORT_CONSOLE_IDLE_STOP_MINUTES=0 turns it off.
#
# @see openspec/changes/support-console/design.md (card ⑨ Machine control)
class SupportConsoleIdleStopJob < ApplicationJob
  queue_as :low

  DEFAULT_IDLE_MINUTES = 60

  def perform
    minutes = Integer(ENV.fetch("SUPPORT_CONSOLE_IDLE_STOP_MINUTES", DEFAULT_IDLE_MINUTES))
    return if minutes <= 0 || !SupportConsoleRelayClient.configured?

    machine = SupportConsoleMachineControl.instance
    return unless machine&.state&.name == "running"
    # E34 — never cut off an answer in progress
    return if SupportConsoleMachineControl.running_turns_count.positive?

    # E35 — idle since the last question or since it was started, whichever is later (EC2 resets
    # launch_time on every start)
    last_active = [SupportConsoleMachineControl.last_question_at, machine.launch_time].compact.max
    return if last_active > minutes.minutes.ago

    # H11
    SupportConsoleMachineControl.stop!(user: nil, reason: "idle #{minutes} min")
    SupportConsoleMachineControl.broadcast_status("stopping")
  end
end
