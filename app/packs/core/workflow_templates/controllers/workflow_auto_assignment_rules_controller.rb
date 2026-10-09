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
      # The condition builder (or View as JSON) posts the conditions as one JSON string
      :conditions_json
    ).tap do |p|
      json = p.delete(:conditions_json)
      next if json.nil?

      # Parsed into a plain array kept off the params: reading it back out of the params would turn
      # each hash into unpermitted Parameters, which then fail on save. Unreadable JSON is stored as
      # the raw string so the save check reports "not a valid list" and the form shows it again.
      p[:conditions] = json.blank? ? [] : parse_conditions(json)
    end
  end

  def parse_conditions(json)
    JSON.parse(json)
  rescue JSON::ParserError
    json
  end

  # The field list for this template's type and the user's entity: drives the builder's dropdowns
  # (workflow-rule-condition-builder card 4). nil for a template with no record type.
  def rule_fields
    return unless WorkflowTemplate::WORKFLOWABLE_TYPE_OPTIONS.include?(@rule.workflowable_type)

    @rule_fields ||= WorkflowRuleFields.for(@rule.workflowable_type, current_user.entity)
  end
  helper_method :rule_fields
end
