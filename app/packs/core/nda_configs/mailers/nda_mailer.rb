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
# @see NdaEventNotifier — Noticed notifier for LP event emails
# @see NdaReminderNotifier — Noticed notifier for LP reminder emails
# @see NdaNotificationRecipients — resolves who gets which email
class NdaMailer < ApplicationMailer
  helper ApplicationHelper
  helper EmailDateLocalization

  # Changed: Sets entity, sender, and direct-to overrides for GP delivery.
  # Why: GP notification_emails are external addresses (not system Users). When
  #   params[:direct_to] is set, we bypass user lookup and set @to directly.
  #   @entity_name is derived here so all 8 email methods can use it in subjects
  #   and template bodies without repeating the lookup.
  before_action :setup_nda_defaults
  def setup_nda_defaults
    @entity = Entity.find(params[:entity_id]) if params[:entity_id]
    @entity_name = @entity&.name
    @from = from_email(@entity) if @entity

    if params[:direct_to].present?
      @to = @entity&.entity_setting&.sandbox ? @entity.entity_setting.sandbox_emails : params[:direct_to]
      @cc = nil
    end
  end

  # @description GP notification: an LP investor accepted the NDA.
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :nda_version,
  #   :signed_by, :signed_at. Plus :direct_to for GP.
  def nda_accepted
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @nda_version = params[:nda_version]
    @signed_by = params[:signed_by]
    @signed_at = params[:signed_at]

    subject = "NDA Accepted — #{@investor_name} on #{@folder_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description LP notification: NDA accepted — investor now has folder access.
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :signed_by,
  #   :signed_at, :folder_link, :contact_email, :notification_id, :user_id
  def nda_acceptance_confirm
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @signed_by = params[:signed_by]
    @signed_at = params[:signed_at]
    @folder_link = params[:folder_link]
    @contact_email = params[:contact_email]

    subject = "Non-Disclosure Agreement Accepted | #{@entity_name}"
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
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :contact_email,
  #   :reason, :revoked_at, :folder_link, :notification_id, :user_id
  def nda_revoked
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @contact_email = params[:contact_email]
    @reason = params[:reason]
    @revoked_at = params[:revoked_at]
    @folder_link = params[:folder_link]

    subject = "Non-Disclosure Agreement Access Revoked | #{@entity_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description LP notification: NDA has a new version, re-acceptance required.
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :old_version,
  #   :new_version, :folder_link, :contact_email, :updated_at, :notification_id, :user_id
  def nda_new_version
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @old_version = params[:old_version]
    @new_version = params[:new_version]
    @folder_link = params[:folder_link]
    @contact_email = params[:contact_email]
    @updated_at = params[:updated_at]

    subject = "Action Required: Accept Updated Non-Disclosure Agreement | #{@entity_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description GP + LP notification: NDA acceptance expiring within 7 days.
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :expiry_date,
  #   :days_until_expiry, :folder_link, :contact_email. Plus :direct_to for GP or
  #   :notification_id/:user_id for LP.
  def nda_expiry_approaching
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @expiry_date = params[:expiry_date]
    @days_until_expiry = params[:days_until_expiry]
    @folder_link = params[:folder_link]
    @contact_email = params[:contact_email]

    subject = "Non-Disclosure Agreement Expiring in 7 Days | #{@entity_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description GP + LP notification: NDA acceptance has expired.
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :expiry_date,
  #   :folder_link, :contact_email. Plus :direct_to for GP or :notification_id/:user_id for LP.
  def nda_expired
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @expiry_date = params[:expiry_date]
    @folder_link = params[:folder_link]
    @contact_email = params[:contact_email]

    subject = "Non-Disclosure Agreement Expired | #{@entity_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end

  # @description LP notification: reminder to accept a pending NDA.
  # @param params [Hash] :entity_id, :investor_name, :folder_name, :folder_link,
  #   :contact_email, :invitation_date, :notification_id, :user_id
  def nda_reminder
    @investor_name = params[:investor_name]
    @folder_name = params[:folder_name]
    @folder_link = params[:folder_link]
    @contact_email = params[:contact_email]
    @invitation_date = params[:invitation_date]

    subject = "Reminder: Non-Disclosure Agreement Pending Acceptance | #{@entity_name}"
    mail(from: @from, to: @to, cc: @cc, subject: subject)
  end
end
