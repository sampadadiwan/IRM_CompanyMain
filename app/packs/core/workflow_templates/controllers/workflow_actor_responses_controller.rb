class WorkflowActorResponsesController < ApplicationController
  before_action :set_folder
  before_action :set_instance

  # POST /folders/:folder_id/workflow_instances/:workflow_instance_id/workflow_actor_responses
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
    # same step are serialised. WorkflowAdvancer.advance is called OUTSIDE this
    # transaction so that deliver_later jobs fire only after the DB commits.
    resolved_state = nil
    ActiveRecord::Base.transaction do
      @instance.lock!
      @response.save!
      result          = WorkflowStepResolver.resolve(@instance.reload)
      resolved_state  = result[:resolved]
    end
    # advance() acquires its own row-level lock and is safe to call outside a transaction.
    if resolved_state
      WorkflowAdvancer.advance(
        @instance,
        resolved_state: resolved_state,
        actor:          current_user,
        channel:        :ui
      )
    end
    redirect_to folder_workflow_instance_path(@folder, @instance),
                notice: "Response \"#{@response.state}\" recorded."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to folder_workflow_instance_path(@folder, @instance),
                alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    redirect_to folder_workflow_instance_path(@folder, @instance),
                alert: "You have already responded to this step."
  end

  private

  def set_folder
    @folder = Folder.find(params[:folder_id])
    # Verify the user has at least view access to the folder before touching its workflow
    authorize @folder, :show?
  end

  def set_instance
    @instance = @folder.workflow_instances.find(params[:workflow_instance_id])
  end

  def response_params
    params.require(:workflow_actor_response).permit(:state, :note)
  end
end
