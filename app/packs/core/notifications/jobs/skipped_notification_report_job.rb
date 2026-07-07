# Reports Noticed::Notification rows that ApplicationMailer#record_notification_skip marked
# (attachment_mandatory was on and a required document was missing for that recipient) but hasn't
# reported yet — scoped to ONE custom notification (the one that just produced a skip), not a
# system-wide sweep. Emails one summary per triggering-admin group for that custom notification —
# to the admin who triggered the send if known, else that entity's company admins.
#
# NOT cron-scheduled: record_notification_skip enqueues this itself (with a short delay) the
# moment it actually marks a skip, so it never runs on a timer when nothing happened. Still a
# stateless "catch up on whatever's unreported for this notification" query rather than tracking
# "batch complete", because each notifier-driven send is an independent job with no shared
# in-memory state to synchronize a batch on — multiple skips from the same trigger may each
# enqueue a run of this job (for the same custom_notification_id), which is harmless since every
# run only ever reports rows still skip_reported_at: nil.
class SkippedNotificationReportJob < ApplicationJob
  queue_as :low

  def perform(custom_notification_id)
    # custom_notification_id isn't a real column (it's stored on the polymorphic event's JSON
    # params), so it can't be pushed into the where(...) itself — but it starts from the already
    # narrow skip_reason/skip_reported_at-indexed set, so filtering the rest in Ruby is cheap.
    # event: :record eager-loads the polymorphic CapitalCommitment/InvestorKyc each notification
    # is about, since error_msg below reads n.event.record for every row.
    skipped = Noticed::Notification.where.not(skip_reason: nil).where(skip_reported_at: nil).includes(event: :record)
                                    .select { |n| n.event.params[:custom_notification_id].to_s == custom_notification_id.to_s }
    return if skipped.empty?

    custom_notification = CustomNotification.find_by(id: custom_notification_id)
    # A CustomNotification belongs to exactly one entity, so entity_id is fixed for this whole
    # run — falls back to a skipped row's own entity_id only if the notification config was since
    # deleted. Only triggered_by_user_id can still vary (different admins triggering the same
    # template at different times), so that's the only thing left to group by.
    entity_id = custom_notification&.entity_id || skipped.first.entity_id

    skipped
      .group_by { |n| n.event.params[:triggered_by_user_id] }
      .each { |triggered_by_user_id, notifications| report_group(entity_id, triggered_by_user_id, custom_notification, notifications) }
  end

  private

  def report_group(entity_id, triggered_by_user_id, custom_notification, notifications)
    to = recipient_email(entity_id, triggered_by_user_id)
    return if to.blank?

    # One line per distinct (record, reason) — collapses multiple recipients who share a
    # commitment/KYC (and therefore the same missing document) into a single reported line.
    error_msg = notifications.map { |n| [n.event.record&.to_s || "Recipient ##{n.recipient_id}", n.skip_reason] }.uniq

    EntityMailer.with(
      to: to,
      error_msg: error_msg,
      subject: "#{custom_notification&.subject || 'Notification'}: recipients skipped for missing attachments",
      entity_id: entity_id,
      filter_url: skipped_notifications_url(entity_id),
      filter_label: "View skipped notifications"
    ).notify_errors.deliver_now

    Noticed::Notification.where(id: notifications.map(&:id)).update_all(skip_reported_at: Time.current)
  end

  # Links straight to the Notifications list, pre-filtered to this entity's skipped rows —
  # same q[...] param shape NotificationsController#index already ransacks. subdomain must be
  # passed explicitly (default_url_options only sets :host) — mirrors the same pattern
  # CapitalCommitmentMailer#adhoc_notification_link uses for capital_commitment_url.
  def skipped_notifications_url(entity_id)
    entity = Entity.find_by(id: entity_id)
    return nil unless entity

    Rails.application.routes.url_helpers.notifications_url(
      subdomain: entity.sub_domain,
      entity_id: entity_id,
      all: 1,
      q: { skip_reason_not_null: 1 }
    )
  end

  # The triggering admin's email if we know who they were, else every company admin for the
  # entity that owns the skipped notification(s) — see Fund#adhoc_notification for the only
  # flow that currently threads triggered_by_user_id through.
  def recipient_email(entity_id, triggered_by_user_id)
    triggering_user_email = User.find_by(id: triggered_by_user_id)&.email if triggered_by_user_id.present?
    triggering_user_email || User.company_admins.where(entity_id: entity_id).pluck(:email).join(",").presence
  end
end
