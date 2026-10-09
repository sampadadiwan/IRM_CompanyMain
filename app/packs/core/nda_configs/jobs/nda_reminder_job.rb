# frozen_string_literal: true

# @description Background job for sending NDA reminders to pending investors' signatories.
#   Triggered on-demand by GP via NdaStatusController#send_reminders.
#   Resolves LP signatory users of investors who haven't accepted the current NDA version,
#   and delivers NdaReminderNotifier to each. GP notification_emails also receive a direct
#   mailer delivery summarising who was reminded.
#
# Changed: Module 8 — new file for manual NDA reminder delivery.
# Why: Reminders are sent in background (deliver_later) so the GP's HTTP response
#   is never blocked by email delivery. Each LP user gets an individual notification
#   via Noticed for standard email_delay and sandbox handling.
#
# @see NdaStatusController#send_reminders
# @see NdaReminderNotifier
# @see NdaNotificationRecipients
class NdaReminderJob < ApplicationJob
  queue_as :default

  # @param nda_config_id [Integer] the NDA config to send reminders for
  # @return [void]
  def perform(nda_config_id)
    nda_config = NdaConfig.find(nda_config_id)
    recipients = NdaNotificationRecipients.resolve(:reminder, nda_config)
    folder_name = nda_config.owner&.name

    # Changed: Deliver to each LP signatory user via Noticed.
    # Why: LP users are system Users — they get the standard Noticed pipeline
    #   with email_delay and sandbox handling.
    recipients[:lp_users].each do |user|
      NdaReminderNotifier.with(
        entity_id: nda_config.entity_id,
        record: nda_config,
        folder_name: folder_name,
        folder_link: folder_link_for(nda_config),
        contact_email: nda_config.contact_email
      ).deliver_later(user)
    end

    Rails.logger.info("[NdaReminderJob] Sent #{recipients[:lp_users].size} reminders for nda_config_id=#{nda_config_id}")
  rescue StandardError => e
    Rails.logger.error("[NdaReminderJob] Failed: #{e.message} (nda_config_id=#{nda_config_id})")
    raise
  end

  private

  # Changed: Use _url instead of _path for absolute URLs in emails.
  # Why: Email clients need full URLs with host — relative paths don't work.
  #
  # @param nda_config [NdaConfig] the NDA config
  # @return [String, nil] the absolute folder URL for email links
  def folder_link_for(nda_config)
    return nil unless nda_config.owner.is_a?(Folder)

    Rails.application.routes.url_helpers.folder_documents_url(
      entity_id: nda_config.entity_id,
      folder_id: nda_config.owner_id
    )
  end
end
