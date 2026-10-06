# frozen_string_literal: true

# @description Noticed notifier for NDA reminder emails delivered to LP signatories.
#   Separate from NdaEventNotifier because reminders have different recipient logic
#   (signatories of Pending investors only) and always use the :nda_reminder method.
#
# Changed: Module 8 — new notifier for GP-triggered NDA reminder emails.
# Why: Reminders target NDA signatories of Pending investors (not all LP users).
#   A separate notifier keeps recipient logic and email_data clean vs branching
#   inside NdaEventNotifier.
#
# @see NdaMailer#nda_reminder — renders the reminder email template
# @see NdaReminderJob — enqueues these notifications for each signatory
# @see NdaNotificationRecipients — resolves which signatories to notify
# @see BaseNotifier — parent class with deliver_by :email configuration
class NdaReminderNotifier < BaseNotifier
  # @return [Class] the mailer class used for email delivery
  def mailer_name(_notification = nil)
    NdaMailer
  end

  # @return [Symbol] always :nda_reminder — this notifier handles only reminders
  def email_method(_notification = nil)
    :nda_reminder
  end

  # @param notification [Noticed::Notification] the delivery notification record
  # @return [Hash] email_data passed to NdaMailer#nda_reminder as params
  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      email_method: :nda_reminder,
      folder_name: params[:folder_name],
      folder_link: params[:folder_link],
      contact_email: params[:contact_email]
    }
  end
end
