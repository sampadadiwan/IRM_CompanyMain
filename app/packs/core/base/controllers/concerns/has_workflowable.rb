module HasWorkflowable
  extend ActiveSupport::Concern

  private

  # Sets @workflowable to the page's primary model object when it supports workflows.
  # Also sets @workflowable_instance and @workflowable_pending_step when the current
  # user has a pending (unresponded) actor assignment on the active step — so the
  # breadcrumb can render an inline response form without a page navigation.
  #
  # Declare in the controller AFTER the model-loading before_action:
  #   before_action :set_workflowable, only: [:show]
  def set_workflowable
    # Skip for unauthenticated requests (e.g. investor magic-link access on KYC show)
    return unless respond_to?(:current_user, true) && current_user.present?

    obj = instance_variable_get(:"@#{controller_name.singularize}")
    return unless obj&.respond_to?(:workflow_instances)

    @workflowable = obj

    # Find the single active instance for this object (there can only be one at a time)
    instance = @workflowable.workflow_instances.instance_active.first
    return unless instance

    @workflowable_instance = instance
    step_data = instance.current_step_data
    return unless step_data

    # Check whether the current user is an actor assigned to this step
    actor_ids = Array(step_data[:actor_ids]).map(&:to_i)
    return unless actor_ids.include?(current_user.id)

    # Only show the action button if they haven't already submitted a response
    already_responded = instance.workflow_actor_responses
                                .active
                                .where(actor_id: current_user.id,
                                       step_position: instance.current_step_position)
                                .exists?
    return if already_responded

    @workflowable_pending_step = step_data
  end
end
