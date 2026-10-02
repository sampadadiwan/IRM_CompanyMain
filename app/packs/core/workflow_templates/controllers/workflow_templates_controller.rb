class WorkflowTemplatesController < ApplicationController
  before_action :set_workflow_template, only: %i[show edit update destroy duplicate toggle_enabled]

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
    # Each kind is offered to its own entity types only (KYC: Angel Funds too; calls: Investment Funds)
    # Worked examples X4 — openspec/changes/investor-kyc-journey/design.md#worked-examples
    raise Pundit::NotAuthorizedError unless setup.available_for?(current_user.entity)

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

  # PATCH /workflow_templates/:id/toggle_enabled
  # Retires a template, or brings it back. Disabling stops it being auto-assigned or launched on any
  # record created from now on (WorkflowAutoAssignmentService, WorkflowInstanceLaunch) — for a
  # journey template that means new capital calls, distributions and KYCs get no journey at all —
  # while every workflow already running keeps evaluating from the snapshot taken at its launch.
  def toggle_enabled
    # One flag, flipped from whatever it is now: the button's label says which way it will go
    was_enabled = @workflow_template.enabled

    # Back to wherever the button was pressed — the list or the template's own page
    if @workflow_template.update(enabled: !was_enabled)
      redirect_back_or_to workflow_template_path(@workflow_template),
                          notice: toggle_enabled_notice(was_enabled)
    else
      # A pre-existing validation failure (e.g. a duplicate name) — say so rather than 500
      redirect_back_or_to workflow_template_path(@workflow_template),
                          alert: "Could not #{was_enabled ? 'disable' : 'enable'} this template: " \
                                 "#{@workflow_template.errors.full_messages.to_sentence}"
    end
  end

  # POST /workflow_templates/:id/duplicate — copy the template and its steps, then edit the copy
  # (e.g. a journey for one KYC form type, routed by a form-type rule). Authorized as duplicate? (= create?).
  # Worked examples E25, E26 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def duplicate
    copy = @workflow_template.duplicate!
    redirect_to workflow_template_path(copy), notice: "Template duplicated as \"#{copy.name}\". Add an auto-assignment rule to use it."
  end

  def destroy
    count = @workflow_template.active_workflowable_count
    if count.positive?
      # Disabling is the way out of an undeletable template: it stops being used without losing history
      redirect_to workflow_templates_path,
                  alert: "Cannot delete a template assigned to #{count} object(s). Remove the assignment first, " \
                         "or disable the template to stop it being used."
      return
    end

    # WorkflowInstance has its own FK to workflow_template_id (non-nullable).
    # Destroying the template while instances exist causes a DB FK violation.
    if WorkflowInstance.where(workflow_template_id: @workflow_template.id).exists?
      redirect_to workflow_templates_path,
                  alert: "Cannot delete a template that has associated workflow history. Archive all instances first, " \
                         "or disable the template to stop it being used."
      return
    end

    @workflow_template.destroy
    redirect_to workflow_templates_path, notice: "Workflow template deleted."
  end

  private

  # What the admin is told after a toggle. Disabling names the consequence that is easy to miss:
  # the template's auto-assignment rules stay on the page but can no longer give a record anything.
  def toggle_enabled_notice(was_enabled)
    return "\"#{@workflow_template.name}\" is enabled again. New records can be assigned and launched on it." unless was_enabled

    rule_count = @workflow_template.workflow_auto_assignment_rules.count
    rules = rule_count.positive? ? " Its #{helpers.pluralize(rule_count, 'auto-assignment rule')} will no longer assign it." : ""
    "\"#{@workflow_template.name}\" is disabled. New records will not be assigned or launched on it; " \
      "workflows already running are unaffected.#{rules}"
  end

  # { kind => the setup's dry-run report } for every journey kind, when the user may run setup
  def journey_setup_plans
    return {} unless policy(WorkflowTemplate.new(entity_id: current_user.entity_id)).setup_journeys?

    kinds = JourneySetup::KINDS.keys.select { |kind| JourneySetup.for_kind(kind).available_for?(current_user.entity) }
    kinds.index_with { |kind| JourneySetup.for_kind(kind).call(entity: current_user.entity, execute: false)[:report] }
  end

  # "Full and Light journeys, auto-assignment rules" from the setup report; nil when nothing was missing
  def journey_setup_summary(report, setup)
    parts = []
    names = { setup::FULL_KEY => setup::FULL_LABEL, setup::LIGHT_KEY => "Light" }
    parts << "#{report[:templates].map { |key| names[key] }.to_sentence} journey#{'s' if report[:templates].size > 1}" if report[:templates].any?
    parts << "auto-assignment rule#{'s' if report[:rules].size > 1}" if report[:rules].any?
    parts << "a #{setup::SIGN_OFF_NAME} step (edit it to pick the approver)" if report[:cfo]
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
