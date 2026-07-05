class WorkflowActorResponsesController < ApplicationController
  before_action :set_instance

  # POST /workflow_instances/:workflow_instance_id/workflow_actor_responses
  def create
    @response = WorkflowActorResponse.new(
      workflow_instance: @instance,
      actor:             current_user,
      step_position:     @instance.current_step_position,
      channel:           :ui,
      responded_at:      Time.current,
      **response_params.to_h.symbolize_keys
    )
    authorize @response

    # Save the response inside a locked transaction so concurrent submissions for the
    # same step are serialised. WorkflowAdvancer is called OUTSIDE this
    # transaction so that deliver_later jobs fire only after the DB commits.
    resolved_state = nil
    ActiveRecord::Base.transaction do
      @instance.lock!
      @response.save!
      result          = WorkflowStepResolver.call(instance: @instance.reload)
      resolved_state  = result[:resolution][:resolved]
    end
    # WorkflowAdvancer acquires its own row-level lock and is safe to call outside a transaction.
    if resolved_state
      WorkflowAdvancer.call(
        instance:       @instance,
        resolved_state: resolved_state,
        actor:          current_user,
        channel:        :ui
      )
    end
    # Redirect back to wherever the actor was (object page or instance page).
    # redirect_back falls back to the instance page if no HTTP Referer is present.
    redirect_back fallback_location: workflow_instance_path(@instance),
                  notice: "Response \"#{@response.state}\" recorded."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: workflow_instance_path(@instance),
                  alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    redirect_back fallback_location: workflow_instance_path(@instance),
                  alert: "You have already responded to this step."
  end

  private

  def set_instance
    # Scope through Pundit so the user can only access instances in their entity
    @instance = policy_scope(WorkflowInstance).find(params[:workflow_instance_id])
  end

  def response_params
    params.require(:workflow_actor_response).permit(:state, :note)
  end
end
