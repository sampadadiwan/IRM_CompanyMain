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

  # Sent daily to the owner of a journey step (system / acknowledge) that has stalled.
  # params: user_id, entity_id, instance_id, step_position, message
  def owner_reminder
    load_journey_context
    @message = params[:message]
    send_mail(subject: "Needs attention: #{@step[:name]} – #{@workflowable_name}")
  end

  # Sent to the owner of a journey acknowledge step the moment it becomes current ("Mark reviewed").
  # params: user_id, entity_id, instance_id, step_position
  def review_needed
    load_journey_context
    send_mail(subject: "Needs your review: #{@step[:name]} – #{@workflowable_name}")
  end

  # Sent to the owner of a journey's last step (or the record's creator) when every step is done.
  # params: user_id, entity_id, instance_id, step_position (the last step)
  def journey_complete
    load_journey_context
    send_mail(subject: "Complete: #{@instance.template_name} – #{@workflowable_name}")
  end

  # Sent to an approver whose sign-off on a journey step was reset because earlier work was undone.
  # params: user_id, entity_id, instance_id, step_position, reason
  def sign_off_reset
    load_journey_context
    @reason = params[:reason]
    send_mail(subject: "Your sign-off was reset: #{@step[:name]} – #{@workflowable_name}")
  end

  private

  # Journey emails go to owners and approvers who act on the record itself, so they carry links
  # to the record and the instance page but no magic link
  def load_journey_context
    @instance          = WorkflowInstance.find(params[:instance_id])
    @workflowable      = @instance.workflowable
    @step              = @instance.snapshot_steps.find { |s| s[:position].to_i == params[:step_position].to_i }
    @workflowable_name = @workflowable.workflow_display_name
    @workflowable_url  = workflowable_full_url(@workflowable)
    @instance_url      = workflow_instance_url(@instance)
  end

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
      # one. This mailer is now sent through WorkflowNotifier, so @notification is set and
      # send_mail's oversize bail would refuse the whole email (recording a skip) if any file got
      # past this check. Checking the whole set here first means @attachments_skipped is set
      # instead and the email still goes out, with the template showing the link.
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
