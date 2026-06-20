class WorkflowTemplatesController < ApplicationController
  before_action :set_workflow_template, only: %i[show edit update destroy]

  def index
    @bread_crumbs = { "Workflow Templates": workflow_templates_path }
    authorize WorkflowTemplate
    @workflow_templates = policy_scope(WorkflowTemplate)
                          .where(entity_id: current_user.entity_id)
                          .includes(:workflow_steps)
                          .order(:name)
  end

  def show; end

  def new
    @bread_crumbs = { "Workflow Templates": workflow_templates_path, New: nil }
    @workflow_template = WorkflowTemplate.new(entity_id: current_user.entity_id)
    # Seed one blank step so the form renders with at least one row
    @workflow_template.workflow_steps.build
    authorize @workflow_template
  end

  def create
    @workflow_template = WorkflowTemplate.new(workflow_template_params)
    @workflow_template.entity_id = current_user.entity_id
    authorize @workflow_template

    if @workflow_template.save
      redirect_to workflow_template_path(@workflow_template),
                  notice: "Workflow template was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @bread_crumbs = { "Workflow Templates": workflow_templates_path,
                      @workflow_template.name => workflow_template_path(@workflow_template),
                      Edit: nil }
  end

  def update
    if @workflow_template.update(workflow_template_params)
      redirect_to workflow_template_path(@workflow_template),
                  notice: "Workflow template was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @workflow_template.active_folder_count.positive?
      redirect_to workflow_templates_path,
                  alert: "Cannot delete a template that is assigned to #{@workflow_template.active_folder_count} folder(s). Remove it from all folders first."
      return
    end

    # WorkflowInstance has its own FK to workflow_template_id (non-nullable).
    # Destroying the template while instances exist causes a DB FK violation.
    if WorkflowInstance.where(workflow_template_id: @workflow_template.id).exists?
      redirect_to workflow_templates_path,
                  alert: "Cannot delete a template that has associated workflow history. Archive all instances first."
      return
    end

    @workflow_template.destroy
    redirect_to workflow_templates_path, notice: "Workflow template deleted."
  end

  private

  def set_workflow_template
    @workflow_template = WorkflowTemplate.find(params[:id])
    authorize @workflow_template
    @bread_crumbs = { "Workflow Templates": workflow_templates_path,
                      @workflow_template.name => workflow_template_path(@workflow_template) }
  end

  def workflow_template_params
    params.require(:workflow_template).permit(
      :name, :description, :reminder_interval_days, :attach_document_in_email,
      workflow_steps_attributes: [
        :id, :position, :name, :description, :states,
        :quorum_rule, :on_reject_rule, :on_reject_target_step,
        :reminder_interval_days, :_destroy,
        actor_user_ids: [],
        workflow_step_actors_attributes: [:id, :user_id, :_destroy]
      ]
    )
  end
end
