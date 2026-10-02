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
      :conditions_json,
      # KYC rules: the "KYC form type" picker (blank = any form type)
      :kyc_form_type_id
    ).tap do |p|
      # Parse the conditions_json string into a plain array, kept in a local: reading it back out of
      # the params would turn each hash into unpermitted Parameters, which then fail on save
      json = p.delete(:conditions_json)
      conditions = JSON.parse(json) if json.present?
      conditions = with_kyc_form_type(conditions || Array(@rule&.conditions), p.delete(:kyc_form_type_id).presence) if p.key?(:kyc_form_type_id)
      p[:conditions] = conditions unless conditions.nil?
    end
  end

  # The picker writes the form-type condition so admins never type a form_type_id: it replaces any
  # form_type_id condition already in the JSON. Only this entity's KYC form types are accepted.
  # Worked examples E25, E27 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def with_kyc_form_type(conditions, form_type_id)
    conditions = Array(conditions).reject { |c| c.is_a?(Hash) && c["attribute"].to_s == "form_type_id" }
    if form_type_id
      form_type = kyc_form_types.find(form_type_id) # raises RecordNotFound for another entity's form type
      conditions << { "attribute" => "form_type_id", "operator" => "eq", "value" => form_type.id.to_s }
    end
    conditions
  end

  # This entity's KYC form types (individual / non-individual, any tag), for the picker
  def kyc_form_types
    current_user.entity.form_types.where(name: WorkflowAutoAssignmentRule::KYC_FORM_TYPE_NAMES)
  end
  helper_method :kyc_form_types
end
