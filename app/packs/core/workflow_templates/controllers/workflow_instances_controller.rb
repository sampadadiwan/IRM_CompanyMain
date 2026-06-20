require 'csv'

class WorkflowInstancesController < ApplicationController
  before_action :set_folder
  before_action :set_instance, only: %i[show advance reset archive send_reminder export_audit_trail]

  # POST /folders/:folder_id/workflow_instances
  def create
    # Allow template to be selected at launch time (from the launch modal dropdown)
    if params[:workflow_template_id].present?
      @folder.update!(workflow_template_id: params[:workflow_template_id])
    end

    @instance = WorkflowInstance.new(folder: @folder, launched_by: current_user)
    authorize @instance

    WorkflowInstanceService.launch(@folder, launched_by: current_user)
    redirect_to folder_path(@folder, anchor: "workflow-tab"),
                notice: "Workflow launched. Step 1 actors have been notified."
  rescue ArgumentError => e
    redirect_to folder_path(@folder, anchor: "workflow-tab"), alert: e.message
  end

  # GET /folders/:folder_id/workflow_instances/:id
  def show
    authorize @instance
    @responses     = @instance.workflow_actor_responses.active.for_step(@instance.current_step_position)
    @current_step  = @instance.current_step_data
    @actor_ids     = Array(@current_step&.dig(:actor_ids)).map(&:to_i)
    @is_actor      = @actor_ids.include?(current_user.id)
    # Preload actor users to avoid N+1 in the view loop
    @actor_users   = User.where(id: @actor_ids).index_by(&:id)
    @resolution    = @instance.instance_active? ? WorkflowStepResolver.resolve(@instance) : nil
    # All active responses grouped by step position — used by the step pipeline to show every actor
    @all_responses_by_step = @instance.workflow_actor_responses.active
                                      .includes(:actor)
                                      .group_by(&:step_position)

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
  end

  # POST /folders/:folder_id/workflow_instances/:id/advance
  # Admin manually sets the resolved state (breaks a tiebreaker or overrides).
  def advance
    authorize @instance
    unless @instance.instance_active?
      redirect_to folder_workflow_instance_path(@folder, @instance), alert: "This workflow is no longer active."
      return
    end
    state = params[:state].to_s.strip
    if state.blank?
      redirect_to folder_workflow_instance_path(@folder, @instance), alert: "State is required."
      return
    end

    WorkflowAdvancer.advance(@instance, resolved_state: state, actor: current_user, channel: :ui,
                             note: params[:note])
    redirect_to folder_workflow_instance_path(@folder, @instance),
                notice: "Step advanced to \"#{state}\"."
  end

  # POST /folders/:folder_id/workflow_instances/:id/reset
  def reset
    authorize @instance
    WorkflowInstanceService.reset(@instance)
    redirect_to folder_workflow_instance_path(@folder, @instance), notice: "Workflow reset to step 1."
  rescue ArgumentError => e
    redirect_to folder_workflow_instance_path(@folder, @instance), alert: e.message
  end

  # POST /folders/:folder_id/workflow_instances/:id/archive
  def archive
    authorize @instance
    WorkflowArchiver.archive(@instance)
    redirect_to folder_path(@folder, anchor: "workflow-tab"), notice: "Workflow archived."
  rescue ArgumentError => e
    redirect_to folder_workflow_instance_path(@folder, @instance), alert: e.message
  end

  # POST /folders/:folder_id/workflow_instances/:id/send_reminder
  # Immediately sends a reminder email to every pending actor on the current step.
  def send_reminder
    authorize @instance
    unless @instance.instance_active?
      redirect_to folder_workflow_instance_path(@folder, @instance),
                  alert: "Reminders can only be sent while the workflow is active."
      return
    end

    step_data = @instance.current_step_data
    unless step_data
      redirect_to folder_workflow_instance_path(@folder, @instance),
                  alert: "Current step data is unavailable."
      return
    end

    responded_ids = @instance.workflow_actor_responses
                             .active
                             .for_step(@instance.current_step_position)
                             .pluck(:actor_id)
    pending_ids = Array(step_data[:actor_ids]).map(&:to_i) - responded_ids

    if pending_ids.empty?
      redirect_to folder_workflow_instance_path(@folder, @instance),
                  notice: "All actors have already responded — no reminders sent."
      return
    end

    pending_ids.each do |actor_id|
      actor = User.find_by(id: actor_id)
      next unless actor

      WorkflowMailer.with(
        user_id:       actor.id,
        entity_id:     @folder.entity_id,
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

    redirect_to folder_workflow_instance_path(@folder, @instance),
                notice: "Reminder emails sent to #{pending_ids.size} pending actor(s)."
  end

  # GET /folders/:folder_id/workflow_instances/:id/export_audit_trail.csv
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

  def set_folder
    @folder = Folder.find(params[:folder_id])
    authorize @folder, :show?
  end

  def set_instance
    @instance = @folder.workflow_instances.find(params[:id])
  end
end
