# frozen_string_literal: true

# The Security Events Download: a spreadsheet of the filtered events, emailed to whoever asked (OWASP review 2026-11
# M11, H31). Modelled on AuditDownloadJob.
#
# X9 — the requester is reloaded and SecurityEventPolicy::Scope applied again here: the params came from a browser,
# so a crafted q[entity_id_eq] (not ransackable, dropped) or a user who lost their admin role since clicking gets
# only what the policy allows now.
class SecurityEventDownloadJob < ApplicationJob
  queue_as :low
  # The params carry the filter (an account name, an IP): not for the Sidekiq log
  self.log_arguments = false
  retry_on StandardError, attempts: 3
  # The requester was deleted since clicking: nothing to send
  discard_on ActiveRecord::RecordNotFound

  # @param filter_params [Hash] SecurityEventFilter#to_params from the screen
  # @param user_id [Integer] the requester
  def perform(filter_params, user_id:)
    user = User.find(user_id)
    # X9 — today's policy for today's user, then the screen's filter
    scope = SecurityEventFilter.new(filter_params).apply(SecurityEventPolicy::Scope.new(user, SecurityEvent).resolve)
    xlsx = SecurityEventWorkbook.new.add_events("Security events", scope).to_stream
    SecurityEventsMailer.with(user_id: user.id, entity_id: user.entity_id, xlsx:,
                              period: [filter_params["from"], filter_params["to"]]).download.deliver_now
  end
end
