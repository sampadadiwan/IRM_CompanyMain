# frozen_string_literal: true

# Sends escalation notifications to the Caphive CS team when the Customer Support
# Agent hands off a conversation to a human. Bypasses standard entity→user flow
# since the recipient is the internal CS queue, not an FM user.
#
# @see CustomerSupportEscalationService
# @see CustomerSupportEscalation
class CustomerSupportEscalationMailer < ApplicationMailer
  prepend_view_path Rails.root.join('app/packs/ai/customer_support_agent/views').to_s
  # Notifies the CS team that a conversation has been escalated.
  #
  # @param escalation_id [Integer] the CustomerSupportEscalation record ID
  def escalation_created
    @escalation = CustomerSupportEscalation.find(params[:escalation_id])
    @session = @escalation.agent_chat_session
    @entity = @escalation.entity
    @user = @escalation.user
    @recent_messages = @session.agent_chat_messages.order(:created_at).last(10)

    subject = "[CS Escalation] #{@entity.name} — #{@escalation.reason.humanize}"

    # Send to support users mapped to this entity; fall back to global support email
    mapped_emails = SupportClientMapping
                    .where(entity_id: @entity.id, enabled: true)
                    .includes(:user)
                    .filter_map { |m| m.user.email }

    recipients = mapped_emails.presence || [ENV.fetch("SUPPORT_EMAIL_TO", "support@caphive.com")]

    mail(
      from: ENV.fetch("SUPPORT_EMAIL_FROM", nil),
      to: recipients,
      subject: subject
    )
  end
end
