require 'csv'

class WorkflowInstancesController < ApplicationController
  # Whitelist prevents arbitrary constant injection via workflowable_type param.
  # Kept in sync with WorkflowTemplate::WORKFLOWABLE_TYPE_OPTIONS by convention —
  # this list is deliberately separate (not a reference to the constant) so a
  # security review of this controller doesn't need to trust another file's contents.
  # CapitalDistribution: capital-distribution-journey (Worked examples H2 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples)
  ALLOWED_WORKFLOWABLE_TYPES = %w[Folder InvestorKyc CapitalCommitment CapitalCall CapitalDistribution Approval Investor].freeze

  before_action :set_instance, only: %i[show advance reset archive send_reminder export_audit_trail acknowledge step_info]

  # GET /workflow_instances
  # Lists all workflow instances visible to the current user's entity.
  # Accepts optional workflow_template_id param to filter by template (used by the template show tab).
  def index
    @instances = policy_scope(WorkflowInstance).includes(:workflow_template, :workflowable)
                                               .order(created_at: :desc)
    @instances = @instances.where(workflow_template_id: params[:workflow_template_id]) if params[:workflow_template_id].present?
    authorize WorkflowInstance
  end

  # POST /workflow_instances
  # Params: workflowable_type, workflowable_id (and optionally workflow_template_id)
  def create
    workflowable = find_workflowable!
    return if performed? # find_workflowable! may redirect on error

    # Allow template to be selected at launch time from the launch modal dropdown.
    # Guard: ensure the template's type scope (if set) matches the workflowable's type.
    if params[:workflow_template_id].present?
      template = WorkflowTemplate.find(params[:workflow_template_id])
      if template.workflowable_type.present? && template.workflowable_type != workflowable.workflowable_type_name
        redirect_to back_url(workflowable),
                    alert: "Template '#{template.name}' can only be used with #{template.workflowable_type} objects."
        return
      end
      unless template.eligible_for?(workflowable)
        redirect_to back_url(workflowable),
                    alert: "Template '#{template.name}' is not applicable to this record."
        return
      end
      # The launch picker already hides disabled templates, but the id arrives as a request
      # parameter — check it here too, before the existing assignment is thrown away below
      unless template.enabled?
        redirect_to back_url(workflowable),
                    alert: "Template '#{template.name}' is disabled and cannot be launched. Enable it first."
        return
      end
      workflowable.workflow_assignment&.destroy
      workflowable.create_workflow_assignment!(workflow_template: template, created_by: current_user)
    end

    @instance = WorkflowInstance.new(workflowable: workflowable, launched_by: current_user,
                                      entity_id: workflowable.entity_id)
    authorize @instance

    result = WorkflowInstanceLaunch.call(workflowable: workflowable, launched_by: current_user)
    if result.success?
      redirect_to back_url(workflowable), notice: "Workflow launched. Step 1 actors have been notified."
    else
      redirect_to back_url(workflowable), alert: result[:errors]
    end
  end

  # GET /workflow_instances/:id
  def show
    authorize @instance
    @workflowable  = @instance.workflowable
    @responses     = @instance.workflow_actor_responses.active.for_step(@instance.current_step_position)
    @current_step  = @instance.current_step_data
    @actor_ids     = Array(@current_step&.dig(:actor_ids)).map(&:to_i)
    @is_actor      = @actor_ids.include?(current_user.id)
    @resolution    = @instance.instance_active? ? WorkflowStepResolver.call(instance: @instance)[:resolution] : nil
    # All active responses grouped by step position — used by the step pipeline to show every actor
    @all_responses_by_step = @instance.workflow_actor_responses.active
                                      .includes(:actor)
                                      .group_by(&:step_position)

    # Preload actor users for every step (not just the current one) so the shared flow-diagram
    # partial can render actor chips + responses across the whole pipeline, not only the active step.
    all_actor_ids = @instance.snapshot_steps.flat_map { |s| Array(s[:actor_ids]) }.map(&:to_i).uniq
    @actor_users  = User.where(id: all_actor_ids).index_by(&:id)

    # Audit trail = individual actor votes only (WorkflowActorResponse), sorted by time.
    # Resolution events (WorkflowStateChange) are used only by the step pipeline via resolved_per_step.
    @history = @instance.workflow_actor_responses
                        .includes(:actor)
                        .order(:responded_at)
                        .map do |r|
      { at: r.responded_at, step: r.step_position,
        actor: r.actor, state: r.state, channel: r.channel,
        note: r.note, archived: r.archived }
    end
    # Resolution events used only for the step pipeline's resolved-state display
    @state_changes = @instance.workflow_state_changes.chronological.includes(:actor)

    resolved_per_step = build_resolved_per_step(@state_changes)
    @step_presenters = @instance.snapshot_steps.map do |snap|
      WorkflowStepDiagramPresenter.for_snapshot_step(
        snap, instance: @instance, actor_users_by_id: @actor_users,
        resolved_state_change: resolved_per_step[snap[:position].to_i],
        actor_responses: @all_responses_by_step[snap[:position].to_i] || [],
        # Journey steps show who stalled-step reminders go to — the job's own lookup, so the
        # diagram can't disagree with who actually gets emailed
        owner_user: (WorkflowAutoReminderJob.owner_for(@instance, snap) if snap[:kind].present? && snap[:kind].to_s != "human")
      )
    end
  end

  # POST /workflow_instances/:id/advance
  # Admin manually sets the resolved state (breaks a tiebreaker or overrides).
  def advance
    authorize @instance
    unless @instance.instance_active?
      redirect_to workflow_instance_path(@instance), alert: "This workflow is no longer active."
      return
    end
    state = params[:state].to_s.strip
    if state.blank?
      redirect_to workflow_instance_path(@instance), alert: "State is required."
      return
    end

    WorkflowAdvancer.call(instance: @instance, resolved_state: state, actor: current_user, channel: :ui,
                          note: params[:note])
    redirect_to workflow_instance_path(@instance),
                notice: "Step advanced to \"#{state}\"."
  end

  # POST /workflow_instances/:id/reset
  def reset
    authorize @instance
    result = WorkflowInstanceReset.call(instance: @instance)
    # Journeys: after a reset the data decides where the instance really is
    WorkflowEvaluator.call(instance: @instance.reload, actor: current_user) if result.success? && @instance.evaluated
    if result.success?
      redirect_to workflow_instance_path(@instance), notice: "Workflow reset to step 1."
    else
      redirect_to workflow_instance_path(@instance), alert: result[:errors]
    end
  end

  # GET /workflow_instances/:id/step_info?position=N
  # The popup a journey step opens when clicked: what to do, what completing it changes, why it
  # exists and who on the team is reminded. Read-only — it shows the step's stored result (what the panel shows), it never
  # re-evaluates. Fetched on click by journey_step_info_controller.js and appended to <body>, outside
  # the journey frame, so the record's page carries none of this and a live update replacing the
  # panel can't strand an open modal.
  def step_info
    # Same gate as the panel: the journey is visible to whoever can see the record
    authorize @instance, :show?
    authorize @instance.workflowable, :show?

    position = params[:position].to_i
    step = @instance.snapshot_steps.find { |s| s[:position].to_i == position }
    return head(:not_found) unless step

    render partial: "workflow_instances/step_info", locals: { instance: @instance, record: @instance.workflowable, step: }
  end

  # Worked examples H4, X3 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  # POST /workflow_instances/:id/acknowledge
  # "Mark reviewed" on the current acknowledge step of a journey. Needs view rights on the
  # instance and update rights on the record (e.g. the capital call) itself.
  def acknowledge
    authorize @instance, :show?
    authorize @instance.workflowable, :update?

    result = WorkflowAcknowledge.call(instance: @instance, step_position: params[:step_position].to_i,
                                      user: current_user)
    respond_to do |format|
      # The panel re-renders either way: on failure it shows the step's current state
      format.turbo_stream { render_journey_frame }
      format.html do
        flash_key, flash_message = result.success? ? [:notice, "Marked as reviewed."] : [:alert, result[:errors]]
        redirect_back_or_to workflow_instance_path(@instance), flash_key => flash_message
      end
    end
  end

  # POST /workflow_instances/:id/archive
  def archive
    authorize @instance
    result = WorkflowArchiver.call(instance: @instance)
    if result.success?
      redirect_to back_url(@instance.workflowable), notice: "Workflow archived."
    else
      redirect_to workflow_instance_path(@instance), alert: result[:errors]
    end
  end

  # POST /workflow_instances/:id/send_reminder
  # Immediately sends a reminder email to every pending actor on the current step.
  def send_reminder
    authorize @instance
    unless @instance.instance_active?
      redirect_to workflow_instance_path(@instance),
                  alert: "Reminders can only be sent while the workflow is active."
      return
    end

    step_data = @instance.current_step_data
    unless step_data
      redirect_to workflow_instance_path(@instance),
                  alert: "Current step data is unavailable."
      return
    end

    responded_ids = @instance.workflow_actor_responses
                             .active
                             .for_step(@instance.current_step_position)
                             .pluck(:actor_id)
    pending_ids = Array(step_data[:actor_ids]).map(&:to_i) - responded_ids

    if pending_ids.empty?
      redirect_to workflow_instance_path(@instance),
                  notice: "All actors have already responded — no reminders sent."
      return
    end

    pending_ids.each do |actor_id|
      actor = User.find_by(id: actor_id)
      next unless actor

      WorkflowNotifier.with(record: @instance, entity_id: @instance.entity_id, # denormalized; no folder join needed
                            email_method: :reminder, step_position: @instance.current_step_position).deliver_later(actor)

      WorkflowStateChange.create!(
        workflow_instance: @instance,
        step_position:     @instance.current_step_position,
        actor:             actor,
        from_state:        nil,
        to_state:          "reminder_sent",
        note:              "Manual reminder sent by #{current_user.full_name}",
        channel:           :auto_reminder
      )
    end

    redirect_to workflow_instance_path(@instance),
                notice: "Reminder emails sent to #{pending_ids.size} pending actor(s)."
  end

  # GET /workflow_instances/:id/export_audit_trail.csv
  def export_audit_trail
    authorize @instance

    actor_rows = @instance.workflow_actor_responses.includes(:actor).order(:responded_at).map do |r|
      [ r.responded_at.strftime("%Y-%m-%d %H:%M:%S UTC"), r.step_position,
        "Vote", r.actor&.full_name || "Unknown",
        "—", r.state, r.channel.humanize, r.note.presence || "",
        r.archived? ? "archived" : "active" ]
    end
    resolution_rows = @instance.workflow_state_changes.chronological.includes(:actor).map do |sc|
      [ sc.created_at.strftime("%Y-%m-%d %H:%M:%S UTC"), sc.step_position,
        "Resolved", sc.actor&.full_name || "System",
        sc.from_state.presence || "—", sc.to_state, sc.channel.humanize,
        sc.note.presence || "", "—" ]
    end
    all_rows = (actor_rows + resolution_rows).sort_by { |r| r[0] }

    csv_string = CSV.generate(headers: true) do |csv|
      csv << ["Timestamp", "Step", "Event", "Actor", "From State", "To State", "Channel", "Note", "Status"]
      all_rows.each { |row| csv << row }
    end

    send_data csv_string,
              filename:    "workflow_audit_#{@instance.id}_#{Date.today}.csv",
              type:        "text/csv",
              disposition: "attachment"
  end

  private

  # Re-renders the record's journey panel in place (capital calls today)
  def render_journey_frame
    record = @instance.workflowable
    journey = WorkflowEvaluator.for(record, cause: :progress)
    render turbo_stream: turbo_stream.replace(record.journey_frame_id,
                                              partial: "#{record.workflowable_type_name.underscore.pluralize}/journey",
                                              locals: { record:, journey: journey&.[](:results), instance: @instance.reload })
  end

  # Safely resolve the workflowable from params, rejecting unknown types
  def find_workflowable!
    type = params[:workflowable_type].to_s
    unless ALLOWED_WORKFLOWABLE_TYPES.include?(type)
      redirect_to root_path, alert: "Invalid workflowable type."
      return nil
    end
    klass = type.constantize
    klass.find(params[:workflowable_id])
  end

  def set_instance
    # Scope to entity via Pundit policy — no folder join needed (entity_id is denormalized)
    @instance = policy_scope(WorkflowInstance).find(params[:id])
  end

  # Last non-reminder WorkflowStateChange per step position. For ACTIVE instances we only
  # look at steps already passed through (step_position < current_step_position) — this
  # prevents stale state changes from previous runs (before a manual reset or an
  # on_reject_rule restart) from showing resolved badges on steps the workflow has returned
  # to. For terminal instances (complete/rejected/archived) we show the full history so every
  # step displays its final resolved state.
  def build_resolved_per_step(state_changes)
    non_reminder_changes = state_changes.reject do |sc|
      sc.channel == "auto_reminder" || sc.to_state == "reminder_sent" || sc.to_state == "reset"
    end

    if @instance.instance_active?
      non_reminder_changes
        .select { |sc| sc.step_position < @instance.current_step_position }
        .group_by(&:step_position)
        .transform_values(&:last)
    else
      non_reminder_changes
        .group_by(&:step_position)
        .transform_values(&:last)
    end
  end

  # After create/archive, send the user back to the workflowable's own page
  def back_url(workflowable)
    return root_path unless workflowable.respond_to?(:workflow_url)
    workflowable.workflow_url
  rescue NotImplementedError
    root_path
  end
end
