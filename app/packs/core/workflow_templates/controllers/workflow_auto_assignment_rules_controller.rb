class WorkflowAutoAssignmentRulesController < ApplicationController
  before_action :set_workflow_template
  before_action :set_rule, only: %i[show edit update destroy]

  # GET /workflow_templates/:workflow_template_id/workflow_auto_assignment_rules
  def index
    authorize WorkflowAutoAssignmentRule
    @rules = policy_scope(WorkflowAutoAssignmentRule)
             .where(workflow_template: @workflow_template, entity: current_user.entity)
             .order(:priority)
  end

  # GET /workflow_templates/:workflow_template_id/workflow_auto_assignment_rules/new
  def new
    @rule = WorkflowAutoAssignmentRule.new(
      entity:            current_entity,
      workflow_template: @workflow_template,
      workflowable_type: @workflow_template.workflowable_type
    )
    authorize @rule
  end

  # POST /workflow_templates/:workflow_template_id/workflow_auto_assignment_rules
  def create
    @rule = WorkflowAutoAssignmentRule.new(rule_params)
    @rule.entity            = current_entity
    @rule.workflow_template = @workflow_template
    @rule.created_by        = current_user
    authorize @rule

    if @rule.save
      redirect_to workflow_template_path(@workflow_template),
                  notice: "Auto-assignment rule created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /workflow_templates/:workflow_template_id/workflow_auto_assignment_rules/:id/edit
  def edit; end

  # PATCH /workflow_templates/:workflow_template_id/workflow_auto_assignment_rules/:id
  def update
    if @rule.update(rule_params)
      redirect_to workflow_template_path(@workflow_template),
                  notice: "Auto-assignment rule updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /workflow_templates/:workflow_template_id/workflow_auto_assignment_rules/:id
  def destroy
    @rule.destroy
    redirect_to workflow_template_path(@workflow_template),
                notice: "Auto-assignment rule deleted."
  end

  private

  def set_workflow_template
    @workflow_template = WorkflowTemplate.find(params[:workflow_template_id])
    @bread_crumbs = {
      "Workflow Templates": workflow_templates_path,
      @workflow_template.name => workflow_template_path(@workflow_template),
      "Auto-assignment Rules": nil
    }
  end

  def set_rule
    @rule = WorkflowAutoAssignmentRule.find(params[:id])
    authorize @rule
  end

  def current_entity
    Entity.find(current_user.entity_id)
  end

  def rule_params
    params.require(:workflow_auto_assignment_rule).permit(
      :workflowable_type, :priority, :auto_launch,
      # conditions come in as a JSON string from a hidden textarea, parsed to an array
      :conditions_json
    ).tap do |p|
      # Parse the conditions_json string into the conditions array attribute
      if p[:conditions_json].present?
        p[:conditions] = JSON.parse(p.delete(:conditions_json))
      else
        p.delete(:conditions_json)
      end
    end
  end
end
