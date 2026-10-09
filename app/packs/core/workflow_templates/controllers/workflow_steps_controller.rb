class WorkflowStepsController < ApplicationController
  before_action :set_workflow_template
  before_action :set_step, only: %i[edit update destroy]

  def new
    @step = @workflow_template.workflow_steps.build(position: next_position)
    authorize @step
    @bread_crumbs = { "Workflow Templates": workflow_templates_path,
                      @workflow_template.name => workflow_template_path(@workflow_template),
                      "New Step": nil }
  end

  def create
    @step = @workflow_template.workflow_steps.build(step_params)
    authorize @step

    if save_through_template
      redirect_to workflow_template_path(@workflow_template),
                  notice: "Step \"#{@step.name}\" added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @bread_crumbs = { "Workflow Templates": workflow_templates_path,
                      @workflow_template.name => workflow_template_path(@workflow_template),
                      "Edit Step": nil }
  end

  def update
    @step.assign_attributes(step_params)

    if save_through_template
      redirect_to workflow_template_path(@workflow_template),
                  notice: "Step updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    # Destroy through the template so the surviving steps close the gap and stay numbered 1..n
    @step.mark_for_destruction
    @workflow_template.save

    redirect_to workflow_template_path(@workflow_template),
                notice: "Step removed."
  end

  private

  def set_workflow_template
    @workflow_template = WorkflowTemplate.find(params[:workflow_template_id])
    authorize @workflow_template, :edit?
  end

  # Pick the step out of the loaded collection rather than re-querying it, so the object the form
  # edits is the same one the template renumbers and autosaves (see save_through_template)
  def set_step
    @step = @workflow_template.workflow_steps.detect { |step| step.id == params[:id].to_i }
    raise ActiveRecord::RecordNotFound, "step #{params[:id]} not found" unless @step

    authorize @step
  end

  # Save a step by saving its template, so WorkflowTemplate's renumbering runs: typing an existing
  # step's number moves this step into that slot and the siblings close ranks, instead of tripping
  # the UNIQUE index on [workflow_template_id, position].
  def save_through_template
    return true if @workflow_template.save

    # Autosave copies the step's own errors onto the template; a failure the step doesn't know
    # about (a template that no longer validates) would otherwise render a form with no message
    @workflow_template.errors.full_messages.each { |message| @step.errors.add(:base, message) } if @step.errors.empty?
    false
  end

  def next_position
    (@workflow_template.workflow_steps.maximum(:position) || 0) + 1
  end

  def step_params
    params.require(:workflow_step).permit(
      :position, :name, :description, :states,
      :quorum_rule, :on_reject_rule, :on_reject_target_step, :reminder_interval_days,
      :notify_on_activation,
      # Journey fields: how the step completes, its check, skip rule, owner and unlocked buttons
      :kind, :check_key, :skip_key, :owner_user_id, :unlocks, :keep_on_regress,
      actor_user_ids: [],
      workflow_step_actors_attributes: [:id, :user_id, :_destroy]
    )
  end
end
