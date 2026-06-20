class WorkflowStepActor < ApplicationRecord
  belongs_to :workflow_step, inverse_of: :workflow_step_actors
  belongs_to :user

  validates :user_id, uniqueness: { scope: :workflow_step_id, message: "is already an actor on this step" }
end
