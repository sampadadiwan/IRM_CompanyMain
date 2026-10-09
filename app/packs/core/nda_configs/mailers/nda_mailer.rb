# frozen_string_literal: true

# @description Mailer for all NDA lifecycle notifications — 8 email methods covering
#   accept, decline, revoke, version change, expiry approaching, expired, acceptance
#   confirmation, and manual reminders.
#
#   Two delivery paths:
#   - **LP users (system Users):** Delivered via NdaEventNotifier/NdaReminderNotifier
#     through Noticed. setup_defaults runs normally (sets @to from @user, applies sandbox).
#   - **GP notification_emails (external addresses):** Delivered directly via
#     NdaMailer.method(params).deliver_later. params[:direct_to] is set, so @to is
#     overridden to the external address. No Noticed::Notification exists.
#
# Changed: Module 8 — new mailer for NDA lifecycle notifications.
# Why: All NDA modules deferred email delivery to Module 8. This mailer centralizes
#   the 8 email types with consistent subject lines and template placeholders.
#
# @see NdaEventNotifier — Noticed notifier for LP event emails
# @see NdaReminderNotifier — Noticed notifier for LP reminder emails
# @see NdaNotificationRecipients — resolves who gets which email
class NdaMailer < ApplicationMailer
  helper ApplicationHelper
  helper EmailDateLocalization

  # Changed: Override setup_defaults to support direct GP delivery.
  # Why: GP notification_emails are external addresses (not system Users). When
  #   params[:direct_to] is set, we bypass user lookup and set @to directly.
  #   Sandbox setting is still honored via entity_setting.
  before_action :setup_nda_defaults
  def setup_nda_defaults
    @entity = Entity.find(params[:entity_id]) if params[:entity_id]
    @from = from_email(@entity) if @entity

    if params[:direct_to].present?
      # Changed: Direct GP delivery — set @to to external email, skip User lookup.
      # Why: notification_emails are free-text external addresses, not system Users.
      @to = @entity&.entity_setting&.sandbox ? @entity.entity_setting.sandbox_emails : params[:direct_to]
      @cc = nil
    end
  end

  # @description GP notification: an LP investor accepted the NDA.
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :nda_version,
  #   :signed_by, :signed_at. Plus :direct_to for GP or :notification_id/:user_id for LP.
  def nda_accepted
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @nda_version = params[:nda_version]
    @signed_by = params[:signed_by]
    @signed_at = params[:signed_at]

    subject = "NDA Accepted — #{@investor_name} on #{@folder_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description LP notification: NDA accepted by a colleague — you now have folder access.
  # @param params [Hash] :entity_id, :folder_name, :signed_by, :signed_at, :folder_link,
  #   :notification_id, :user_id
  def nda_acceptance_confirm
    @folder_name = params[:folder_name]
    @signed_by = params[:signed_by]
    @signed_at = params[:signed_at]
    @folder_link = params[:folder_link]

    subject = "NDA Access Granted — #{@folder_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description GP notification: an LP investor declined the NDA.
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :nda_version,
  #   :declined_by, :declined_at, :direct_to
  def nda_declined
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @nda_version = params[:nda_version]
    @declined_by = params[:declined_by]
    @declined_at = params[:declined_at]

    subject = "NDA Declined — #{@investor_name} on #{@folder_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description LP notification: GP revoked the investor's NDA acceptance.
  # @param params [Hash] :entity_id, :folder_name, :contact_email, :reason,
  #   :notification_id, :user_id
  def nda_revoked
    @folder_name = params[:folder_name]
    @contact_email = params[:contact_email]
    @reason = params[:reason]

    subject = "NDA Access Revoked — #{@folder_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description LP notification: NDA has a new version, re-acceptance required.
  # @param params [Hash] :entity_id, :folder_name, :old_version, :new_version,
  #   :folder_link, :notification_id, :user_id
  def nda_new_version
    @folder_name = params[:folder_name]
    @old_version = params[:old_version]
    @new_version = params[:new_version]
    @folder_link = params[:folder_link]

    subject = "NDA Updated — #{@folder_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description GP + LP notification: NDA acceptance expiring in 7 days.
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :expiry_date,
  #   :days_until_expiry, :folder_link. Plus :direct_to for GP or :notification_id/:user_id for LP.
  def nda_expiry_approaching
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @expiry_date = params[:expiry_date]
    @days_until_expiry = params[:days_until_expiry]
    @folder_link = params[:folder_link]

    subject = "NDA Expiring Soon — #{@investor_name} on #{@folder_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description GP + LP notification: NDA acceptance has expired.
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :expiry_date,
  #   :folder_link. Plus :direct_to for GP or :notification_id/:user_id for LP.
  def nda_expired
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @expiry_date = params[:expiry_date]
    @folder_link = params[:folder_link]

    subject = "NDA Expired — #{@investor_name} on #{@folder_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description LP notification: reminder to accept a pending NDA.
  # @param params [Hash] :entity_id, :folder_name, :folder_link, :contact_email,
  #   :notification_id, :user_id
  def nda_reminder
    @folder_name = params[:folder_name]
    @folder_link = params[:folder_link]
    @contact_email = params[:contact_email]

    subject = "NDA Reminder — #{@folder_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end
end
