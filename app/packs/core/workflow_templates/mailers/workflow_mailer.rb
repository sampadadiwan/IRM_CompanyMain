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
    @instance     = WorkflowInstance.find(params[:instance_id])
    @folder       = @instance.folder
    step_position = params[:step_position].to_i
    @step         = @instance.snapshot_steps.find { |s| s[:position].to_i == step_position }

    # Build the personalised magic link for this actor + step
    token        = WorkflowMagicLinkService.new.generate_token(
      actor_id:      @user.id,
      instance_id:   @instance.id,
      step_position: step_position
    )
    @magic_link  = workflow_magic_link_url(token)

    # Optionally attach all documents in the folder to the email
    if @instance.template_snapshot.with_indifferent_access[:attach_document_in_email]
      @folder.documents.each { |doc| attach_doc(doc) }
    end
  end
end
