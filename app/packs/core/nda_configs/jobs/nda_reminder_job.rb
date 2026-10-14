# frozen_string_literal: true

# @description Background job for sending NDA reminders to pending investors' signatories.
#   Triggered on-demand by GP via NdaStatusController#send_reminders.
#   Resolves LP signatory users grouped by investor, so each reminder email includes the
#   correct investor company name in the greeting. Delivers via NdaReminderNotifier (Noticed).
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
    folder_name = nda_config.owner&.name
    folder_link = folder_link_for(nda_config)
    total_sent = 0

    # Changed: Loop per-investor instead of a flat user list.
    # Why: Updated email template includes "Dear [Investor Name]," greeting. Each user
    #   needs the investor company name they belong to, which requires grouping by investor.
    lp_by_investor = NdaNotificationRecipients.pending_signatory_users_by_investor(nda_config)
    lp_by_investor.each do |investor, users|
      users.each do |user|
        NdaReminderNotifier.with(
          entity_id: nda_config.entity_id,
          record: nda_config,
          investor_name: investor.name,
          folder_name: folder_name,
          folder_link: folder_link,
          contact_email: nda_config.contact_email,
          invitation_date: nda_config.created_at
        ).deliver_later(user)
        total_sent += 1
      end
    end

    Rails.logger.info("[NdaReminderJob] Sent #{total_sent} reminders for nda_config_id=#{nda_config_id}")
  rescue StandardError => e
    Rails.logger.error("[NdaReminderJob] Failed: #{e.message} (nda_config_id=#{nda_config_id})")
    raise
  end

  private

  # @param nda_config [NdaConfig] the NDA config
  # @return [String, nil] the absolute folder URL for email CTA links
  def folder_link_for(nda_config)
    return nil unless nda_config.owner.is_a?(Folder)

    Rails.application.routes.url_helpers.folder_documents_url(
      entity_id: nda_config.entity_id,
      folder_id: nda_config.owner_id
    )
  end
end
