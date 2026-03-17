# Controller for managing Agent Schedules.
#
# Provides CRUD operations for AgentSchedule records and handles
# execution history viewing. All actions require authorization
# through Pundit policies on the associated SupportAgent.
#
# @example Routes
#   GET    /support_agents/:support_agent_id/agent_schedule     # show
#   POST   /support_agents/:support_agent_id/agent_schedule     # create
#   PATCH  /support_agents/:support_agent_id/agent_schedule     # update
#   DELETE /support_agents/:support_agent_id/agent_schedule     # destroy
#   GET    /support_agents/:support_agent_id/agent_schedule/executions # executions
#
# @see AgentSchedule
# @see AgentExecutionLog
class AgentSchedulesController < ApplicationController
  before_action :set_support_agent
  before_action :set_agent_schedule, only: %i[show update destroy]

  # Displays the schedule configuration and recent execution history for a support agent.
  #
  # @return [void]
  # @response_format html
  def show
    @execution_logs = @agent_schedule&.execution_logs&.recent&.limit(20) || []
  end

  # Creates a new schedule or updates an existing one for the support agent.
  # Uses find_or_initialize_by to allow idempotent schedule creation.
  #
  # @return [void]
  # @response_format html, json
  def create
    @agent_schedule = AgentSchedule.find_or_initialize_by(
      support_agent: @support_agent,
      entity_id: @support_agent.entity_id
    )
    @agent_schedule.assign_attributes(agent_schedule_params)
    @agent_schedule.created_by ||= current_user

    if @agent_schedule.save
      respond_to do |format|
        format.html { redirect_to support_agent_path(@support_agent, tab: 'schedule'), notice: "Schedule saved successfully." }
        format.json { render json: schedule_json(@agent_schedule), status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to support_agent_path(@support_agent, tab: 'schedule'), alert: @agent_schedule.errors.full_messages.join(", ") }
        format.json { render json: { errors: @agent_schedule.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  # Updates an existing schedule for a support agent.
  #
  # @return [void]
  # @response_format html, json
  def update
    if @agent_schedule.update(agent_schedule_params)
      respond_to do |format|
        format.html { redirect_to support_agent_path(@support_agent, tab: 'schedule'), notice: "Schedule updated successfully." }
        format.json { render json: schedule_json(@agent_schedule), status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to support_agent_path(@support_agent, tab: 'schedule'), alert: @agent_schedule.errors.full_messages.join(", ") }
        format.json { render json: { errors: @agent_schedule.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  # Deletes the schedule for a support agent.
  # Associated execution logs are nullified (not deleted) to preserve history.
  #
  # @return [void]
  # @response_format html, json
  def destroy
    @agent_schedule.destroy!
    respond_to do |format|
      format.html { redirect_to support_agent_path(@support_agent), notice: "Schedule deleted successfully.", status: :see_other }
      format.json { render json: { status: "deleted" }, status: :ok }
    end
  end

  # Returns paginated execution history for the agent.
  # Shows all executions (both scheduled and manual) for the agent/entity combination.
  #
  # @return [void]
  # @response_format json
  def executions
    @execution_logs = AgentExecutionLog
                      .for_agent_entity(@support_agent.id, @support_agent.entity_id)
                      .recent
                      .page(params[:page])
                      .per(20)

    render json: @execution_logs.map { |log| execution_log_json(log) }
  end

  # Returns details for a specific execution log entry.
  # Used for displaying execution details in a modal or detail view.
  # Scopes the query to the current support agent to prevent IDOR.
  #
  # @return [void]
  # @response_format json
  # @raise [ActiveRecord::RecordNotFound] if the execution log doesn't exist or belongs to another agent
  def execution
    @execution_log = AgentExecutionLog
                     .where(support_agent: @support_agent)
                     .find(params[:execution_id])
    authorize @support_agent

    render json: execution_log_json(@execution_log)
  end

  private

  # Loads and authorizes the support agent from the URL parameter.
  #
  # @return [void]
  # @raise [ActiveRecord::RecordNotFound] if the support agent doesn't exist
  # @raise [Pundit::NotAuthorizedError] if the user lacks permission
  def set_support_agent
    @support_agent = SupportAgent.find(params[:support_agent_id])
    authorize @support_agent
  end

  # Loads the agent schedule for the current support agent and entity.
  # May return nil if no schedule exists yet.
  #
  # @return [void]
  def set_agent_schedule
    @agent_schedule = AgentSchedule.find_by(
      support_agent: @support_agent,
      entity_id: @support_agent.entity_id
    )
  end

  # Permits and returns the allowed parameters for creating/updating a schedule.
  #
  # @return [ActionController::Parameters] permitted schedule parameters
  def agent_schedule_params
    params.require(:agent_schedule).permit(
      :frequency,
      :run_on_day,
      :run_at_time,
      :timezone,
      :enabled,
      :retry_count,
      :retry_interval_minutes,
      :notify_on_success,
      :notify_on_failure,
      :notify_on_partial_success,
      :notify_caphive_on_error,
      failure_notification_user_ids: []
    )
  end

  # Serializes an AgentSchedule to a JSON-compatible hash.
  #
  # @param schedule [AgentSchedule] the schedule to serialize
  # @return [Hash] JSON representation of the schedule
  def schedule_json(schedule)
    {
      id: schedule.id,
      support_agent_id: schedule.support_agent_id,
      entity_id: schedule.entity_id,
      frequency: schedule.frequency,
      run_on_day: schedule.run_on_day,
      run_at_time: schedule.run_at_time&.strftime('%H:%M'),
      timezone: schedule.timezone,
      enabled: schedule.enabled,
      retry_count: schedule.retry_count,
      retry_interval_minutes: schedule.retry_interval_minutes,
      notify_on_failure: schedule.notify_on_failure,
      failure_notification_user_ids: schedule.failure_notification_user_ids,
      next_run_at: schedule.next_run_at&.iso8601,
      last_run_at: schedule.last_run_at&.iso8601,
      currently_running: schedule.currently_running?
    }
  end

  # Serializes an AgentExecutionLog to a JSON-compatible hash.
  #
  # @param log [AgentExecutionLog] the execution log to serialize
  # @return [Hash] JSON representation of the execution log
  def execution_log_json(log)
    {
      id: log.id,
      trigger_type: log.trigger_type,
      status: log.status,
      attempt_number: log.attempt_number,
      started_at: log.started_at&.iso8601,
      completed_at: log.completed_at&.iso8601,
      duration: log.duration_formatted,
      error_message: log.error_message,
      result_summary: log.result_summary,
      triggered_by: log.triggered_by&.name
    }
  end
end
