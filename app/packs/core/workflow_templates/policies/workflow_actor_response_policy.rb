class WorkflowActorResponsePolicy < ApplicationPolicy
  # An actor may only submit a response if they are assigned to the current step
  # and the instance is still active.
  def create?
    instance = record.workflow_instance
    return false unless instance.instance_active?

    step_data = instance.current_step_data
    return false unless step_data

    actor_ids = Array(step_data[:actor_ids]).map(&:to_i)
    actor_ids.include?(user.id)
  end
end
