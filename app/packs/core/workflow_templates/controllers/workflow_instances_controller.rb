require 'csv'

class WorkflowInstancesController < ApplicationController
  # Whitelist prevents arbitrary constant injection via workflowable_type param
  ALLOWED_WORKFLOWABLE_TYPES = %w[Folder InvestorKyc CapitalCommitment Approval].freeze

  before_action :set_instance, only: %i[show advance reset archive send_reminder export_audit_trail]

  # GET /workflow_instances
  # Lists all workflow instances visible to the current user's entity
  def index
    @instances = policy_scope(WorkflowInstance).includes(:workflow_template, :workflowable)
                                               .order(created_at: :desc)
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
      if template.workflowable_type.present? && template.workflowable_type != workflowable.class.name
        redirect_to back_url(workflowable),
                    alert: "Template '#{template.name}' can only be used with #{template.workflowable_type} objects."
        return
      end
      workflowable.workflow_assignment&.destroy
      workflowable.create_workflow_assignment!(workflow_template: template, created_by: current_user)
    end

    @instance = WorkflowInstance.new(workflowable: workflowable, launched_by: current_user)
    authorize @instance

    WorkflowInstanceService.launch(workflowable, launched_by: current_user)
    redirect_to back_url(workflowable), notice: "Workflow launched. Step 1 actors have been notified."
  rescue ArgumentError => e
    redirect_to back_url(workflowable), alert: e.message
  end

  # GET /workflow_instances/:id
  def show
    authorize @instance
    @workflowable  = @instance.workflowable
    @responses     = @instance.workflow_actor_responses.active.for_step(@instance.current_step_position)
    @current_step  = @instance.current_step_data
    @actor_ids     = Array(@current_step&.dig(:actor_ids)).map(&:to_i)
    @is_actor      = @actor_ids.include?(current_user.id)
    @resolution    = @instance.instance_active? ? WorkflowStepResolver.resolve(@instance) : nil
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
        actor_responses: @all_responses_by_step[snap[:position].to_i] || []
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

    WorkflowAdvancer.advance(@instance, resolved_state: state, actor: current_user, channel: :ui,
                             note: params[:note])
    redirect_to workflow_instance_path(@instance),
                notice: "Step advanced to \"#{state}\"."
  end

  # POST /workflow_instances/:id/reset
  def reset
    authorize @instance
    WorkflowInstanceService.reset(@instance)
    redirect_to workflow_instance_path(@instance), notice: "Workflow reset to step 1."
  rescue ArgumentError => e
    redirect_to workflow_instance_path(@instance), alert: e.message
  end

  # POST /workflow_instances/:id/archive
  def archive
    authorize @instance
    WorkflowArchiver.archive(@instance)
    redirect_to back_url(@instance.workflowable), notice: "Workflow archived."
  rescue ArgumentError => e
    redirect_to workflow_instance_path(@instance), alert: e.message
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

      WorkflowMailer.with(
        user_id:       actor.id,
        entity_id:     @instance.entity_id,   # denormalized; no folder join needed
        instance_id:   @instance.id,
        step_position: @instance.current_step_position
      ).reminder.deliver_later

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
