# frozen_string_literal: true

# Starts or stops the support machine for a support user's button, then follows it until it is up
# (the relay answers) or down, refreshing the badge on every open console page as it goes.
#
# Same shape as DbRestoreJob: one Sidekiq job per action, no retries — a failed start is shown on
# the badge and the user presses Start again.
#
# @see openspec/changes/support-console/design.md (card ⑨ Machine control)
class SupportConsoleMachineJob < ApplicationJob
  # Not the support_console capsule: its 3 threads are for questions, and this waits up to 5 minutes
  queue_as :default
  sidekiq_options retry: 0

  STOP_TIMEOUT = 3.minutes

  # @param action [String] start | stop
  # @param user_id [Integer] who pressed the button
  def perform(action, user_id)
    user = User.find_by(id: user_id)
    case action
    when "start"
      # H7 — start, then wait for the relay so "running" means a question will work
      SupportConsoleMachineControl.start!(user: user, reason: "button")
      SupportConsoleMachineControl.broadcast_status("starting")
      SupportConsoleMachineControl.wait_until_healthy
    when "stop"
      # H8 — stop, then wait for EC2 to report it stopped
      SupportConsoleMachineControl.stop!(user: user, reason: "button")
      SupportConsoleMachineControl.broadcast_status("stopping")
      wait_until_stopped
    end
    SupportConsoleMachineControl.broadcast_status
  end

  private

  def wait_until_stopped
    deadline = Time.current + STOP_TIMEOUT
    sleep SupportConsoleMachineControl::POLL_INTERVAL until SupportConsoleMachineControl.instance&.state&.name != "stopping" || Time.current > deadline
  end
end
