class WorkflowMailer < ApplicationMailer
  # params: user_id, entity_id, instance_id, step_position
  # setup_defaults (from ApplicationMailer before_action) sets @user, @entity, @to, @from

  # Skip files larger than this threshold — too large to email safely
  MAX_ATTACHMENT_BYTES = 10.megabytes

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
    token        = WorkflowMagicLinkService.new.generate_token(
      actor_id:      @user.id,
      instance_id:   @instance.id,
      step_position: step_position
    )
    @magic_link  = workflow_magic_link_url(token)

    # Optionally attach the workflowable's associated files to the email.
    # If any file is over the size threshold, skip all attachments and flag for
    # the template to show a fallback link instead.
    if @instance.template_snapshot.with_indifferent_access[:attach_document_in_email]
      files = @workflowable.workflow_attachable_files
      oversized = files.any? { |doc| attachment_byte_size(doc) > MAX_ATTACHMENT_BYTES }
      if oversized
        @attachments_skipped = true   # template displays a note + link instead of files
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

  # Returns the byte size of a document's attached file without downloading it.
  # Supports ActiveStorage blobs (byte_size on the blob) and File objects (size).
  def attachment_byte_size(doc)
    file = doc.try(:file)
    return 0 unless file
    # ActiveStorage: file.blob.byte_size; plain File: file.size
    file.respond_to?(:blob) ? file.blob.byte_size : file.size.to_i
  rescue StandardError
    0 # treat unknown size as small to avoid skipping silently
  end
end
