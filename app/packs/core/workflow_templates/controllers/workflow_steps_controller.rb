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

    if @step.save
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
    if @step.update(step_params)
      redirect_to workflow_template_path(@workflow_template),
                  notice: "Step updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @step.destroy
    redirect_to workflow_template_path(@workflow_template),
                notice: "Step removed."
  end

  # PATCH /workflow_templates/:workflow_template_id/workflow_steps/reorder
  # Receives { positions: { step_id => new_position, ... } } from Stimulus drag controller
  # Authorization is enforced by set_workflow_template (:edit? on the parent template)
  def reorder
    ActiveRecord::Base.transaction do
      params[:positions].each do |step_id, pos|
        @workflow_template.workflow_steps.find(step_id).update!(position: pos.to_i)
      end
    end
    head :ok
  end

  private

  def set_workflow_template
    @workflow_template = WorkflowTemplate.find(params[:workflow_template_id])
    authorize @workflow_template, :edit?
  end

  def set_step
    @step = @workflow_template.workflow_steps.find(params[:id])
    authorize @step
  end

  def next_position
    (@workflow_template.workflow_steps.maximum(:position) || 0) + 1
  end

  def step_params
    params.require(:workflow_step).permit(
      :position, :name, :description, :states,
      :quorum_rule, :on_reject_rule, :on_reject_target_step, :reminder_interval_days,
      actor_user_ids: [],
      workflow_step_actors_attributes: [:id, :user_id, :_destroy]
    )
  end
end
