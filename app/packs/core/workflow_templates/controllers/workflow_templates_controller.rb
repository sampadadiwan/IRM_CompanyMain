class WorkflowTemplatesController < ApplicationController
  before_action :set_workflow_template, only: %i[show edit update destroy]

  def index
    @bread_crumbs = { "Workflow Templates": workflow_templates_path }
    authorize WorkflowTemplate
    @workflow_templates = policy_scope(WorkflowTemplate)
                          .where(entity_id: current_user.entity_id)
                          .includes(:workflow_steps, :workflow_auto_assignment_rules)
                          .order(:name)
    # Per journey kind, what its "Set up … journeys" button would add (a dry run, writes nothing);
    # empty when the user may not run setup (no buttons), an empty plan shows that kind as done
    @journey_setup_plans = journey_setup_plans
  end

  # POST /workflow_templates/setup_journeys?kind=capital_call
  # Seeds a kind's Full and Light journeys and their auto-assignment rules for the user's entity —
  # the same JourneySetup subclass the rollout rake task runs, so UI and rake can't drift.
  # Idempotent: anything already there (including an admin's edits) is kept; existing records get no journey.
  # Worked examples H1, E14, E15 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  # Worked examples H10, E20, X3 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def setup_journeys
    authorize WorkflowTemplate.new(entity_id: current_user.entity_id)

    # Only kinds listed in JourneySetup::KINDS; nothing is constantized from the parameter
    setup = JourneySetup::KINDS.key?(params[:kind].to_s) && JourneySetup.for_kind(params[:kind])
    return redirect_to(workflow_templates_path, alert: "Unknown journey type.") unless setup

    title = setup::LABEL.upcase_first
    result = setup.call(entity: current_user.entity)
    if result.success?
      added = journey_setup_summary(result[:report], setup)
      redirect_to workflow_templates_path,
                  notice: added ? "#{title} set up: #{added}. New #{setup::RECORD.pluralize} will get a journey." : "#{title} were already set up."
    else
      redirect_to workflow_templates_path, alert: "#{title} could not be set up."
    end
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
    count = @workflow_template.active_workflowable_count
    if count.positive?
      redirect_to workflow_templates_path,
                  alert: "Cannot delete a template assigned to #{count} object(s). Remove the assignment first."
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

  # { kind => the setup's dry-run report } for every journey kind, when the user may run setup
  def journey_setup_plans
    return {} unless policy(WorkflowTemplate.new(entity_id: current_user.entity_id)).setup_journeys?

    JourneySetup::KINDS.keys.index_with { |kind| JourneySetup.for_kind(kind).call(entity: current_user.entity, execute: false)[:report] }
  end

  # "Full and Light journeys, auto-assignment rules" from the setup report; nil when nothing was missing
  def journey_setup_summary(report, setup)
    parts = []
    names = { setup::FULL_KEY => "Full", setup::LIGHT_KEY => "Light" }
    parts << "#{report[:templates].map { |key| names[key] }.to_sentence} journey#{'s' if report[:templates].size > 1}" if report[:templates].any?
    parts << "auto-assignment rules" if report[:rules].any?
    parts << "a #{JourneySetup::CFO_STEP_NAME} step (edit it to pick the approver)" if report[:cfo]
    parts.join(", ").presence
  end

  def set_workflow_template
    @workflow_template = WorkflowTemplate.find(params[:id])
    authorize @workflow_template
    @bread_crumbs = { "Workflow Templates": workflow_templates_path,
                      @workflow_template.name => workflow_template_path(@workflow_template) }
  end

  def workflow_template_params
    params.require(:workflow_template).permit(
      :name, :description, :reminder_interval_days, :attach_document_in_email, :workflowable_type,
      :gated_button_labels,
      workflow_steps_attributes: [
        :id, :position, :name, :description, :states,
        :quorum_rule, :on_reject_rule, :on_reject_target_step,
        :reminder_interval_days, :notify_on_activation, :_destroy,
        actor_user_ids: [],
        workflow_step_actors_attributes: [:id, :user_id, :_destroy]
      ]
    )
  end
end
