# frozen_string_literal: true

# @description Daily cron job that scans all enabled NDA configs for approaching
#   and expired acceptances. Sends notification type #6 (approaching, 7-day warning)
#   and type #7 (expired) to GP notification_emails and LP signatories.
#
#   Uses NdaExpiryReminder as an idempotency guard (at-most-once per investor
#   per expiry_date per kind). Follows the ObligationEnforcement pattern.
#
# Changed: Module 8 — new daily cron job for NDA expiry alerts.
# Why: Expiry is time-based — no controller trigger exists. A daily scan
#   classifies each accepted investor's NDA as approaching/expired and
#   sends the appropriate notification once, guarded by NdaExpiryReminder.
#
# @see NdaExpiryReminder — idempotency guard
# @see NdaEventNotifier — LP notification delivery
# @see NdaMailer — GP direct email delivery
# @see NdaNotificationRecipients — recipient resolution
# @see ObligationEnforcement — pattern this follows
class NdaExpiryCheckJob < ApplicationJob
  queue_as :default

  APPROACHING_DAYS = 7

  # @return [void]
  def perform
    NdaConfig.where(enabled: true).find_each do |nda_config|
      process_config(nda_config)
    rescue StandardError => e
      # Changed: Rescue per-config errors to continue scanning other configs.
      # Why: One broken config should not block expiry alerts for other entities.
      Rails.logger.error("[NdaExpiryCheckJob] Config #{nda_config.id} failed: #{e.message}")
    end
  end

  private

  # @param nda_config [NdaConfig] an enabled NDA config to scan
  # @return [void]
  def process_config(nda_config)
    # Changed: Skip configs with no time-based expiry (until_revoked never expires).
    # Why: Only fixed_period and specific_date configs can have approaching/expired states.
    return if nda_config.validity_type == "until_revoked"

    accepted_investors = latest_accepted_investors(nda_config)
    return if accepted_investors.empty?

    folder_name = nda_config.owner&.name

    accepted_investors.each do |investor_id, acceptance|
      # Changed: Skip version-mismatched acceptances — they show as "Expired (version)"
      #   on the dashboard but are not time-expiry alerts.
      # Why: Version bump notifications are sent instantly by NdaConfigsController#update.
      #   The cron job only handles time-based expiry.
      next if acceptance.nda_version != nda_config.version

      expiry_date = compute_expiry_date(nda_config, acceptance)
      next if expiry_date.nil?

      kind = classify(expiry_date)
      next if kind.nil?
      next if NdaExpiryReminder.already_sent?(nda_config.id, investor_id, expiry_date, kind)

      investor = Investor.find(investor_id)
      send_expiry_notification(nda_config, investor, acceptance, kind, expiry_date, folder_name)
      record_reminder(nda_config, investor, expiry_date, kind)
    end
  end

  # @param nda_config [NdaConfig] the NDA config
  # @return [Hash{Integer => NdaAcceptance}] investor_id → latest accepted NdaAcceptance
  def latest_accepted_investors(nda_config)
    subquery = NdaAcceptance
               .where(nda_config_id: nda_config.id, status: "accepted")
               .group(:investor_id)
               .select("investor_id, MAX(created_at) AS max_created_at")

    NdaAcceptance
      .joins("INNER JOIN (#{subquery.to_sql}) latest ON nda_acceptances.investor_id = latest.investor_id AND nda_acceptances.created_at = latest.max_created_at")
      .where(nda_config_id: nda_config.id, status: "accepted")
      .index_by(&:investor_id)
  end

  # @param nda_config [NdaConfig] the NDA config with validity settings
  # @param acceptance [NdaAcceptance] the latest accepted record
  # @return [Date, nil] the computed expiry date, or nil if no expiry applies
  def compute_expiry_date(nda_config, acceptance)
    case nda_config.validity_type
    when "fixed_period"
      (acceptance.accepted_at + nda_config.validity_days.days).to_date
    when "specific_date"
      nda_config.validity_date
    end
  end

  # @param expiry_date [Date] the computed expiry date
  # @return [String, nil] "approaching" if within 7 days, "expired" if past, nil otherwise
  def classify(expiry_date)
    today = Date.current
    if expiry_date < today
      "expired"
    elsif expiry_date <= today + APPROACHING_DAYS
      "approaching"
    end
  end

  # @param nda_config [NdaConfig] the NDA config
  # @param investor [Investor] the investor whose NDA is approaching/expired
  # @param acceptance [NdaAcceptance] the latest acceptance
  # @param kind [String] "approaching" or "expired"
  # @param expiry_date [Date] the computed expiry date
  # @param folder_name [String, nil] the folder name for email context
  # @return [void]
  def send_expiry_notification(nda_config, investor, acceptance, kind, expiry_date, folder_name)
    email_method = kind == "approaching" ? :nda_expiry_approaching : :nda_expired
    recipients = NdaNotificationRecipients.resolve(kind.to_sym, nda_config, investor)

    # Changed: Added folder_link for email CTA.
    # Why: LP needs a clickable link in expiry emails to re-accept the NDA.
    folder_link = folder_link_for(nda_config)

    shared_params = {
      entity_id: nda_config.entity_id,
      investor_name: investor.name,
      folder_name: folder_name,
      expiry_date: expiry_date,
      contact_email: nda_config.contact_email,
      folder_link: folder_link
    }

    # Changed: Send directly to each GP notification email (not through Noticed).
    # Why: notification_emails are external addresses, not system Users.
    recipients[:gp_emails].each do |email|
      NdaMailer.with(shared_params.merge(direct_to: email)).public_send(email_method).deliver_later
    end

    # Changed: Send LP expiry notification via Noticed to signatories.
    # Why: LP signatory users are system Users — they get the standard Noticed pipeline.
    recipients[:lp_users].each do |user|
      NdaEventNotifier.with(
        shared_params.merge(
          email_method: email_method,
          record: acceptance
        )
      ).deliver_later(user)
    end
  end

  # @param nda_config [NdaConfig] the NDA config
  # @return [String, nil] the absolute folder URL for email links
  def folder_link_for(nda_config)
    return nil unless nda_config.owner.is_a?(Folder)

    Rails.application.routes.url_helpers.folder_documents_url(
      entity_id: nda_config.entity_id,
      folder_id: nda_config.owner_id
    )
  end

  # @param nda_config [NdaConfig] the NDA config
  # @param investor [Investor] the investor
  # @param expiry_date [Date] the computed expiry date
  # @param kind [String] "approaching" or "expired"
  # @return [void]
  def record_reminder(nda_config, investor, expiry_date, kind)
    NdaExpiryReminder.create!(
      nda_config: nda_config,
      investor: investor,
      expiry_date: expiry_date,
      kind: kind
    )
  rescue ActiveRecord::RecordNotUnique
    # Changed: Silently rescue duplicate index violation on concurrent race.
    # Why: Two job runs overlapping would both try to insert the same dedup row.
    #   The unique index ensures at-most-once, and the second insert is harmless.
  end
end
