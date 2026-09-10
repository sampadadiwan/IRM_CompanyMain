# frozen_string_literal: true

# The weekly task digest — one email per opted-in fund employee, every Friday.
# See docs/product/weekly_task_digest_prd.md and WeeklyTaskDigestJob.
#
# Takes user_id/entity_id as params rather than an address list so
# ApplicationMailer#setup_defaults resolves the from address, CC, reply-to and —
# importantly — sandbox redirection (entity_setting.sandbox -> sandbox_emails) the
# same way every other user-addressed mailer does.
class TaskDigestMailer < ApplicationMailer
  helper EmailStyleHelper
  helper TaskDigestHelper
  helper ApplicationHelper

  def weekly_digest
    # @user, @entity and @to are already set by ApplicationMailer#setup_defaults
    # from params[:user_id] / params[:entity_id].
    @as_of = params[:as_of].present? ? Date.parse(params[:as_of].to_s) : Time.zone.today
    @digest = WeeklyTaskDigest.new(@user, @entity, as_of: @as_of).call

    # The job checks this too and normally skips the enqueue. Re-checked here
    # because the digest is rebuilt at delivery time, which can be minutes or (on a
    # backed-up queue) hours after the job ran — by which point the last open task
    # may have been closed.
    return record_empty_digest_skip if @digest.empty?

    send_mail(subject: subject_line)
  end

  private

  # The notification row already exists by the time we get here — the notifier writes it
  # before any delivery method runs. Returning without calling mail() leaves
  # mark_delivered to bail on @_mail_was_called, so the row would sit at
  # email_sent = false with a nil subject: indistinguishable from a send that actually
  # failed, while the in-app bell still shows the digest line. Stamping skip_reason is
  # what separates "nothing left to say" from "SES rejected it".
  #
  # Not ApplicationMailer#record_notification_skip: that one is bound to
  # @custom_notification (it schedules SkippedNotificationReportJob with the custom
  # notification's id) and the digest has none.
  def record_empty_digest_skip
    @notification&.update_columns(
      skip_reason: "Weekly task digest was empty at delivery time",
      entity_id: @entity&.id
    )
  rescue StandardError => e
    Rails.logger.error("record_empty_digest_skip failed for notification #{@notification&.id}: #{e.message}")
  end

  # Leads with the number that decides whether the mail gets opened.
  #   Weekly Tasks — 7 delayed, 12 due next week — Alpha Fund I
  #   Weekly Tasks — all on track, 12 due next week — Alpha Fund I
  def subject_line
    counts = @digest.counts
    status = counts[:delayed].zero? ? "all on track" : "#{counts[:delayed]} delayed"
    "Weekly Tasks — #{status}, #{counts[:due_next_week]} due next week — #{@entity.name}"
  end
end
