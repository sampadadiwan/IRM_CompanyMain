class WorkflowStepDiagramPresenter
  attr_reader :mode, :position, :name, :description, :state_list,
              :quorum_rule, :on_reject_rule, :on_reject_target_step,
              :reminder_interval_days, :reminder_active,
              :actor_users, :workflow_step,
              :status, :resolved_state_change, :actor_responses

  def self.for_template_step(step)
    new(mode: :template, workflow_step: step,
        position: step.position, name: step.name, description: step.description,
        state_list: step.state_list, quorum_rule: step.quorum_rule,
        on_reject_rule: step.on_reject_rule, on_reject_target_step: step.on_reject_target_step,
        reminder_interval_days: step.effective_reminder_interval,
        reminder_active: step.reminder_interval_days_before_type_cast.present?,
        actor_users: step.actor_users.to_a)
  end

  def self.for_snapshot_step(snap, instance:, actor_users_by_id:, resolved_state_change:, actor_responses:)
    pos = snap[:position].to_i
    status = if pos == instance.current_step_position && instance.instance_active?
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
        actor_users: actor_ids.filter_map { |id| actor_users_by_id[id] },
        status: status, resolved_state_change: resolved_state_change,
        actor_responses: actor_responses)
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

  def response_for(user)
    actor_responses.find { |r| r.actor_id == user.id }
  end

  private

  def initialize(mode:, position:, name:, description:, state_list:, quorum_rule:,
                 on_reject_rule:, on_reject_target_step:, reminder_interval_days:,
                 reminder_active:, actor_users:, workflow_step: nil, status: nil,
                 resolved_state_change: nil, actor_responses: [])
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
    @actor_users = actor_users
    @workflow_step = workflow_step
    @status = status
    @resolved_state_change = resolved_state_change
    @actor_responses = actor_responses
  end
end
