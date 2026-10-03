class WorkflowStepDiagramPresenter
  attr_reader :mode, :position, :name, :description, :state_list,
              :quorum_rule, :on_reject_rule, :on_reject_target_step,
              :reminder_interval_days, :reminder_active, :notify_on_activation,
              :actor_users, :workflow_step,
              :status, :resolved_state_change, :actor_responses,
              :kind, :owner_user

  def self.for_template_step(step)
    new(mode: :template, workflow_step: step,
        position: step.position, name: step.name, description: step.description,
        state_list: step.state_list, quorum_rule: step.quorum_rule,
        on_reject_rule: step.on_reject_rule, on_reject_target_step: step.on_reject_target_step,
        reminder_interval_days: step.effective_reminder_interval,
        reminder_active: step.reminder_interval_days_before_type_cast.present?,
        notify_on_activation: step.notify_on_activation,
        actor_users: step.actor_users.to_a,
        # Journey steps show their owner instead of approvers; nil = falls back to the record's creator
        kind: step.kind, owner_user: step.owner_user)
  end

  # owner_user: who WorkflowAutoReminderJob.owner_for would remind for this step (nil = nobody)
  def self.for_snapshot_step(snap, instance:, actor_users_by_id:, resolved_state_change:, actor_responses:,
                             owner_user: nil)
    pos = snap[:position].to_i
    status = if instance.evaluated
               # Journeys: the evaluator's last result says what each step is, not the pointer alone
               journey_status(instance.step_result(pos))
             elsif pos == instance.current_step_position && instance.instance_active?
               :current
             elsif pos < instance.current_step_position || instance.instance_complete? ||
                   (instance.instance_rejected? && pos <= instance.current_step_position)
               :done
             else
               :pending
             end
    actor_ids = Array(snap[:actor_ids]).map(&:to_i)

    new(mode: :instance,
        position: pos, name: snap[:name], description: snap[:description],
        state_list: snap[:states].to_s.split(",").map(&:strip).reject(&:blank?),
        quorum_rule: snap[:quorum_rule], on_reject_rule: snap[:on_reject_rule],
        on_reject_target_step: snap[:on_reject_target_step],
        reminder_interval_days: snap[:reminder_interval_days],
        reminder_active: snap[:reminder_interval_days].present?,
        notify_on_activation: snap[:notify_on_activation],
        actor_users: actor_ids.filter_map { |id| actor_users_by_id[id] },
        status: status, resolved_state_change: resolved_state_change,
        actor_responses: actor_responses,
        # Snapshots taken before journeys existed have no kind — they are human steps
        kind: snap[:kind].presence || "human", owner_user: owner_user)
  end

  # Maps an evaluated step's stored status to the diagram's three states
  def self.journey_status(result)
    case result&.dig("status")
    when "passed", "na" then :done
    when "current", "error" then :current
    else :pending
    end
  end

  def template_mode?
    mode == :template
  end

  def instance_mode?
    mode == :instance
  end

  def done?
    status == :done
  end

  def current?
    status == :current
  end

  def pending?
    status == :pending
  end

  def resolved?
    resolved_state_change.present?
  end

  # System (data check) and acknowledge ("Mark reviewed") steps aren't voted on: quorum, actors,
  # activation email and the reject rule don't apply — the diagram shows the kind and owner instead
  def evaluated?
    kind.to_s != "human"
  end

  def silent?
    !notify_on_activation
  end

  def response_for(user)
    actor_responses.find { |r| r.actor_id == user.id }
  end

  private

  def initialize(mode:, position:, name:, description:, state_list:, quorum_rule:,
                 on_reject_rule:, on_reject_target_step:, reminder_interval_days:,
                 reminder_active:, notify_on_activation:, actor_users:, workflow_step: nil,
                 status: nil, resolved_state_change: nil, actor_responses: [], kind: "human", owner_user: nil)
    @mode = mode
    @position = position
    @name = name
    @description = description
    @state_list = state_list
    @quorum_rule = quorum_rule
    @on_reject_rule = on_reject_rule
    @on_reject_target_step = on_reject_target_step
    @reminder_interval_days = reminder_interval_days
    @reminder_active = reminder_active
    @notify_on_activation = notify_on_activation
    @actor_users = actor_users
    @workflow_step = workflow_step
    @status = status
    @resolved_state_change = resolved_state_change
    @actor_responses = actor_responses
    @kind = kind
    @owner_user = owner_user
  end
end
