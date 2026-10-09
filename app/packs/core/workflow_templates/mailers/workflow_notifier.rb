class WorkflowNotifier < BaseNotifier
  # Every workflow message goes through here: step activation, reminders, owner reminders, sign-off
  # resets, "needs your review" and "journey complete". WorkflowMailer still renders the email
  # (subject, body, magic link unchanged); the notifier adds the notification log, the template's
  # Send email / Send WhatsApp switches and the employee-only WhatsApp.
  #
  #   WorkflowNotifier.with(record: instance, entity_id: instance.entity_id,
  #                         email_method: :review_needed, step_position: 4).deliver_later(owner)
  #
  # There is no CustomNotification: custom_notification is nil, so BaseNotifier's email always uses
  # the default body and its shared (investor) :whats_app never fires. WhatsApp goes out only via
  # :employee_whats_app below.
  required_param :entity_id, :email_method, :step_position

  # Text shown on WhatsApp, per email — the same wording as the email subject
  WHATSAPP_MESSAGES = {
    "step_activation" => "Action required: %<step>s – %<record>s",
    "reminder" => "Reminder: %<step>s – %<record>s",
    "owner_reminder" => "Needs attention: %<step>s – %<record>s",
    "sign_off_reset" => "Your sign-off was reset: %<step>s – %<record>s",
    "review_needed" => "Needs your review: %<step>s – %<record>s",
    "journey_complete" => "Complete: %<template>s – %<record>s"
  }.freeze

  # Hard off in test, like BaseNotifier's own WhatsApp: the send is a real HTTP call to WATI
  deliver_by :employee_whats_app, class: "DeliveryMethods::EmployeeWhatsApp" do |config|
    config.if = -> { !Rails.env.test? && notify_by_whatsapp? }
    config.wait = :email_delay
  end

  def mailer_name(_notification = nil)
    WorkflowMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      instance_id: record.id,
      step_position: params[:step_position],
      # Only owner_reminder / sign_off_reset carry these
      message: params[:message],
      reason: params[:reason]
    }.compact
  end

  notification_methods do
    # The template's "Send email" switch. It hooks this method rather than email_enabled because
    # BaseNotifier gates :email on custom_notification_body_present? in every environment (and on
    # email_enabled only outside test), so the switch also holds in Cucumber. Read from the live
    # template, not the launch snapshot, so switching it off silences runs already in flight.
    def custom_notification_body_present?
      super && workflow_template&.notify_by_email != false
    end

    # The template's "Send WhatsApp" switch; who may receive it is DeliveryMethods::EmployeeWhatsApp's job
    def notify_by_whatsapp?
      workflow_template&.notify_by_whatsapp == true
    end

    delegate :workflow_template, to: :record

    def custom_notification
      nil
    end

    # Shown in the notification log and used as the WhatsApp text
    def message
      step = record.snapshot_steps.find { |s| s[:position].to_i == params[:step_position].to_i }
      format(WHATSAPP_MESSAGES.fetch(params[:email_method].to_s, "%<template>s – %<record>s"),
             step: step&.dig(:name), template: record.template_name, record: record.workflowable.workflow_display_name)
    end

    def whatsapp_message
      message
    end

    # The run page — the WhatsApp template's link and the notification log's link
    def url
      workflow_instance_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
