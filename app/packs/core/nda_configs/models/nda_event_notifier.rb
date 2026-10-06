# frozen_string_literal: true

# @description Noticed notifier for NDA lifecycle event emails delivered to LP system Users.
#   Handles acceptance confirmation, revocation, version change, and expiry alerts.
#   Each event type is distinguished by the :email_method param, which maps to the
#   corresponding NdaMailer method.
#
#   GP notification_emails are NOT delivered through this notifier — they are sent
#   directly via NdaMailer.deliver_later because they are external email addresses,
#   not system Users. Only LP users (real User records) go through this Noticed pipeline.
#
# Changed: Module 8 — new notifier for NDA event notifications to LP users.
# Why: LP users need the standard Noticed delivery pipeline (email_delay, email_enabled
#   gating, sandbox handling, delivery tracking). External GP emails bypass this.
#
# @see NdaMailer — renders the email templates
# @see NdaNotificationRecipients — resolves which LP users receive each event
# @see BaseNotifier — parent class with deliver_by :email configuration
class NdaEventNotifier < BaseNotifier
  # @return [Class] the mailer class used for email delivery
  def mailer_name(_notification = nil)
    ::NdaMailer
  end

  # @return [Symbol] the NdaMailer method to call, from params[:email_method]
  def email_method(_notification = nil)
    params[:email_method]
  end

  # @param notification [Noticed::Notification] the delivery notification record
  # @return [Hash] email_data passed to NdaMailer as params
  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      email_method: params[:email_method],
      # Changed: Pass all template placeholders through to NdaMailer.
      # Why: Each email method reads its own subset of these params. Passing all
      #   avoids per-method branching here — the mailer ignores irrelevant keys.
      investor_name: params[:investor_name],
      folder_name: params[:folder_name],
      folder_link: params[:folder_link],
      nda_version: params[:nda_version],
      signed_by: params[:signed_by],
      signed_at: params[:signed_at],
      declined_by: params[:declined_by],
      declined_at: params[:declined_at],
      contact_email: params[:contact_email],
      reason: params[:reason],
      old_version: params[:old_version],
      new_version: params[:new_version],
      expiry_date: params[:expiry_date],
      days_until_expiry: params[:days_until_expiry]
    }
  end
end
