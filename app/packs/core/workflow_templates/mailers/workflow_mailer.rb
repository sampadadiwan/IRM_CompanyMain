class WorkflowMailer < ApplicationMailer
  # params: user_id, entity_id, instance_id, step_position
  # setup_defaults (from ApplicationMailer before_action) sets @user, @entity, @to, @from

  # Sent when a step becomes the active step — either on launch or after the prior step passes.
  def step_activation
    load_step_context
    send_mail(subject: "Action Required: #{@instance.template_name} – #{@step[:name]}")
  end

  # Sent by the auto-reminder job when a step is still pending after reminder_interval_days.
  def reminder
    load_step_context
    send_mail(subject: "Reminder: #{@instance.template_name} – #{@step[:name]}")
  end

  private

  def load_step_context
    @instance      = WorkflowInstance.find(params[:instance_id])
    @workflowable  = @instance.workflowable
    step_position  = params[:step_position].to_i
    @step          = @instance.snapshot_steps.find { |s| s[:position].to_i == step_position }

    # Human-readable object name and deep link for the email body
    @workflowable_name = @workflowable.workflow_display_name
    @workflowable_url  = workflowable_full_url(@workflowable)

    # Direct link to the workflow instance timeline page
    @instance_url = workflow_instance_url(@instance)

    # Build the personalised magic link for this actor + step
    token = WorkflowMagicLinkGenerate.call(
      actor_id: @user.id,
      instance_id: @instance.id,
      step_position: step_position
    )[:token]
    @magic_link = workflow_magic_link_url(token)

    # Optionally attach the workflowable's associated files to the email.
    # If any file is over the size threshold, skip all attachments and flag for
    # the template to show a fallback link instead.
    if @instance.template_snapshot.with_indifferent_access[:attach_document_in_email]
      files = @workflowable.workflow_attachable_files
      # Must use the same rule as ApplicationMailer#attachment_allowed?, not a looser local
      # one. This mailer is invoked directly (WorkflowStepActorNotifier, WorkflowAutoReminderJob,
      # WorkflowInstancesController#send_reminders) with no notification_id, so @notification is
      # nil and send_mail's oversize bail — which is guarded on @notification to keep previews
      # rendering — does not apply here. If the shared guard refused a file that this check had
      # waved through, the step email would go out silently missing its document, with no
      # fallback link and no skip recorded. Checking the whole set here means @attachments_skipped
      # is set instead and the template shows the link.
      oversized = NotificationAttachmentPreflight.violations(files).any?
      if oversized
        @attachments_skipped = true # template displays a note + link instead of files
      else
        files.each { |doc| attach_doc(doc) }
      end
    end
  end

  # Derives the full URL for the workflowable using the <model>_url convention.
  # Falls back to nil if the model has no standard route — the email will skip the link.
  def workflowable_full_url(workflowable)
    helper = :"#{workflowable.class.name.underscore}_url"
    public_send(helper, workflowable)
  rescue NoMethodError
    nil
  end
end
