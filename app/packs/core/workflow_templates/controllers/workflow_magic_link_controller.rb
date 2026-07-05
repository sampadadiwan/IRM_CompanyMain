class WorkflowMagicLinkController < ApplicationController
  # No authentication required — the signed token is the credential.
  skip_before_action :verify_authenticity_token, :authenticate_user!, :set_current_entity
  # Pundit's verify_authorized is not applicable since these actions are unauthenticated.
  skip_after_action :verify_authorized

  before_action :verify_magic_link_token

  # GET /workflow_magic_links/:token
  # Shows the step's response form (or already-responded / moved-on / invalid states).
  def show
    @token        = params[:token]
    @workflowable = @instance.workflowable
    @step         = @instance.current_step_data
    # Guard: current_step_data is nil only if the snapshot is corrupt/missing the step
    return render(:invalid, status: :unprocessable_entity) if @step.nil?

    @actor = User.find_by(id: @payload[:actor_id])

    # Check whether this actor has already submitted for the current step
    @existing_response = @instance.workflow_actor_responses
                                  .active
                                  .for_step(@payload[:step_position].to_i)
                                  .find_by(actor_id: @payload[:actor_id])
  end

  # POST /workflow_magic_links/:token/submit
  # Records the actor's response and triggers step resolution.
  def submit
    state = params[:state].to_s.strip
    note  = params[:note].to_s.strip.presence
    actor = User.find_by(id: @payload[:actor_id])
    return render(:invalid, status: :unprocessable_entity) unless actor && state.present?

    response = WorkflowActorResponse.new(
      workflow_instance: @instance,
      actor:             actor,
      step_position:     @payload[:step_position].to_i,
      channel:           :email_magic_link,
      responded_at:      Time.current,
      state:             state,
      note:              note
    )

    # Save the response inside a locked transaction; WorkflowAdvancer is called OUTSIDE so that
    # deliver_later jobs fire only after the DB commits (WorkflowAdvancer has its own lock).
    resolved_state = nil
    ActiveRecord::Base.transaction do
      @instance.lock!
      response.save!
      result         = WorkflowStepResolver.call(instance: @instance.reload)
      resolved_state = result[:resolution][:resolved]
    end
    if resolved_state
      WorkflowAdvancer.call(
        instance:       @instance,
        resolved_state: resolved_state,
        actor:          actor,
        channel:        :email_magic_link
      )
    end

    redirect_to workflow_magic_link_path(params[:token]),
                notice: "Your response \"#{state}\" has been recorded. Thank you."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to workflow_magic_link_path(params[:token]),
                alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    redirect_to workflow_magic_link_path(params[:token]),
                alert: "You have already responded to this step."
  end

  private

  # Verifies the signed token, resolves the instance, and guards against stale/invalid links.
  # Sets @payload and @instance for both show and submit.
  def verify_magic_link_token
    @payload = WorkflowMagicLinkVerify.call(token: params[:token])[:payload]
    return render(:invalid, status: :unprocessable_entity) unless @payload

    @instance = WorkflowInstance.find_by(id: @payload[:instance_id])
    # Completely unknown instance — token is garbage or instance was hard-deleted.
    return render(:invalid, status: :unprocessable_entity) unless @instance

    # Instance is no longer active (complete / rejected / archived) — the workflow has
    # concluded. Find the actor's response so moved_on can show "thank you" vs "not needed".
    unless @instance.instance_active?
      @previous_response = @instance.workflow_actor_responses
                                    .for_step(@payload[:step_position].to_i)
                                    .find_by(actor_id: @payload[:actor_id])
      return render(:moved_on)
    end

    # Instance is still active but this step has already advanced (another actor hit quorum).
    if @payload[:step_position].to_i != @instance.current_step_position
      @previous_response = @instance.workflow_actor_responses
                                    .for_step(@payload[:step_position].to_i)
                                    .find_by(actor_id: @payload[:actor_id])
      return render(:moved_on)
    end
  end
end
