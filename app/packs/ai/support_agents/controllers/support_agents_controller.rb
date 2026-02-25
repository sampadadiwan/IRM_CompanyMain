# Controller for managing Support Agents and their execution.
#
# Provides CRUD operations for SupportAgent records and handles
# agent execution with step-by-step progress tracking via Turbo Streams.
#
# @see SupportAgent
# @see SupportAgentJob
# @see SupportAgentReport
class SupportAgentsController < ApplicationController
  before_action :set_support_agent, only: %i[show edit update destroy]

  # Lists all support agents accessible by the current user.
  #
  # @return [void]
  def index
    @q = SupportAgent.ransack(params[:q])
    @support_agents = policy_scope(@q.result)
  end

  # Displays a single support agent.
  #
  # @return [void]
  def show; end

  # Initializes a new support agent for creation.
  #
  # @return [void]
  def new
    @support_agent = SupportAgent.new(support_agent_params)
    @support_agent.entity_id = current_user.entity_id
    authorize @support_agent
  end

  # Renders the edit form for a support agent.
  #
  # @return [void]
  def edit; end

  # Creates a new support agent.
  #
  # @return [void]
  def create
    @support_agent = SupportAgent.new(support_agent_params)
    @support_agent.entity_id = current_user.entity_id
    authorize @support_agent
    if @support_agent.save
      redirect_to @support_agent, notice: "Support agent was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Updates an existing support agent.
  #
  # @return [void]
  def update
    if @support_agent.update(support_agent_params)
      redirect_to @support_agent, notice: "Support agent was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Deletes a support agent.
  #
  # @return [void]
  def destroy
    @support_agent.destroy!
    redirect_to support_agents_url, notice: "Support agent was successfully destroyed.", status: :see_other
  end

  # Enqueues a support agent job for execution without step tracking.
  #
  # @return [void]
  def run
    @support_agent = SupportAgent.find_by(agent_type: params[:agent_type], entity_id: current_user.entity_id)
    authorize @support_agent
    # Enqueue the job to run the support agent
    SupportAgentJob.perform_later(support_agent_id: @support_agent.id, target_id: params[:target_id], user_id: current_user.id)
    # Redirect to referrer or support_agents_path if no referrer
    redirect_to(request.referer || support_agents_path, notice: "Support agent job has been queued.")
  end

  # Runs the agent with step-by-step progress tracking.
  #
  # Initializes steps from the agent's step definitions and creates/updates
  # a SupportAgentReport to track progress. Responds with Turbo Stream updates
  # for real-time UI feedback.
  #
  # @return [void]

  # rubocop:disable Metrics/MethodLength
  def run_with_steps
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent

    target = find_target(params[:target_type], params[:target_id])
    return render json: { status: "error", message: "Target not found" }, status: :not_found unless target

    # Check if already running
    existing_report = SupportAgentReport.find_by(owner: target, support_agent: @support_agent)
    return render json: { status: "error", message: "Agent already running for this target" }, status: :unprocessable_entity if existing_report&.running?

    # Enqueue the job
    SupportAgentJob.perform_later(
      support_agent_id: @support_agent.id,
      target_id: params[:target_id],
      target_type: params[:target_type],
      user_id: current_user.id,
      with_steps: @support_agent.with_steps
    )

    # Return the report info for Turbo Stream subscription
    # Initialize steps from the agent's step definitions
    steps = @support_agent.agent.step_definitions.map do |step_def|
      {
        "step" => step_def[:step],
        "id" => step_def[:id],
        "label" => step_def[:label],
        "short_label" => step_def[:short_label],
        "status" => "pending"
      }
    end

    report = SupportAgentReport.find_or_create_by(owner: target, support_agent: @support_agent) do |r|
      r.status = :pending
      r.json_fields = {
        "steps" => steps,
        "final_status" => "running",
        "run_at" => Time.current.iso8601
      }
    end

    respond_to do |format|
      format.html { redirect_to(request.referer || support_agents_path, notice: "Support agent job has been queued.") }
      format.turbo_stream do
        target = find_target(params[:target_type], params[:target_id])
        render turbo_stream: turbo_stream.replace(
          "progress_panel_new",
          partial: "support_agents/progress_panel",
          locals: { report: report, support_agent: @support_agent, target: target }
        )
      end

      format.json do
        render json: {
          status: "started",
          report_id: report.id,
          stream: "support_agent_report_#{report.id}",
          steps: @support_agent.agent.step_definitions
        }, status: :accepted
      end
    end
  end
  # rubocop:enable Metrics/MethodLength

  # Cancels a running agent execution.
  #
  # Updates the report status to failed and records cancellation metadata.
  #
  # @return [void]
  def cancel
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent

    report = SupportAgentReport.find(params[:report_id])

    return render json: { status: "error", message: "Agent is not running" }, status: :unprocessable_entity unless report.running?

    report.json_fields["cancelled_at"] = Time.current.iso8601
    report.json_fields["cancelled_by_user_id"] = current_user.id
    report.json_fields["final_status"] = "cancelled"
    report.status = :failed
    report.save!

    respond_to do |format|
      format.html { redirect_to(request.referer || support_agents_path, notice: "Agent cancelled.") }
      format.json { render json: { status: "cancelled", cancelled_at: report.json_fields["cancelled_at"] } }
    end
  end

  # Returns the current execution status for a target.
  #
  # @return [void]
  def status
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent

    target = find_target(params[:target_type], params[:target_id])
    return render json: { status: "error", message: "Target not found" }, status: :not_found unless target

    report = SupportAgentReport.find_by(owner: target, support_agent: @support_agent)

    if report.nil?
      render json: { report_id: nil, final_status: "never_run" }
    else
      render json: {
        report_id: report.id,
        final_status: report.final_status,
        run_at: report.run_at&.iso8601,
        steps: report.steps,
        failed_step: report.json_fields["failed_step"]
      }
    end
  end

  # Returns the step details partial for a specific step.
  #
  # @return [void]
  def step_details
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent

    report = SupportAgentReport.find(params[:report_id])
    step_num = params[:step_num].to_i

    step = report.steps.find { |s| s["step"] == step_num }

    if step
      render partial: "support_agents/step_details", locals: { step: step, report: report, support_agent: @support_agent }
    else
      render plain: "Step not found", status: :not_found
    end
  end

  private

  # Finds a target record by type and ID.
  #
  # @param target_type [String] the class name of the target
  # @param target_id [Integer, String] the ID of the target record
  # @return [ApplicationRecord, nil] the target record or nil if not found
  def find_target(target_type, target_id)
    return nil unless target_type.present? && target_id.present?

    target_type.constantize.find_by(id: target_id)
  rescue NameError
    nil
  end

  # Sets the support agent and authorizes access.
  #
  # @return [void]
  def set_support_agent
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent
    @bread_crumbs = { 'Support Agents': support_agents_path, "#{@support_agent.name}": support_agent_path(@support_agent) }
  end

  # Permits trusted parameters for support agent creation/update.
  #
  # @return [ActionController::Parameters] permitted parameters
  def support_agent_params
    params.require(:support_agent).permit(:name, :description, :entity_id, :form_type_id, :agent_type, :json_fields, :document_folder_id, :with_steps, properties: {})
  end
end
