class TasksController < ApplicationController
  before_action :set_task, only: %i[show edit update destroy completed destroy_series]
  after_action :verify_authorized, except: %i[index search]
  after_action :verify_policy_scoped, only: []

  # GET /tasks or /tasks.json
  def index
    result = TaskList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = result.q
    @tasks = result.tasks

    @for_entity = params[:for_entity_id].present? ? Entity.find(params[:for_entity_id]) : current_user.entity
    @tasks = with_owner_access(@tasks, raise_error: false)

    @pagy, @tasks = pagy(@tasks)
  end

  def search
    @search = true
    query = params[:query]
    if query.present?
      @tasks = TaskIndex.filter(term: { entity_id: current_user.entity_id })
                        .or(TaskIndex.filter(term: { for_entity_id: current_user.entity_id })
                      .query(simple_query_string: { fields: TaskIndex::SEARCH_FIELDS,
                                                    query:, default_operator: 'and' }))

      @pagy, @tasks = pagy(@tasks.page(params[:page]).objects)
      render "index"
    else
      redirect_to tasks_path(request.parameters)
    end
  end

  # GET /tasks/1 or /tasks/1.json
  def show; end

  # GET /tasks/new
  def new
    @task = params[:task] ? Task.new(task_params) : Task.new
    @task.entity_id ||= @task.owner&.entity_id || current_user.entity_id
    @task.due_date = Time.zone.today + 1.week
    @task.user = current_user
    authorize @task
    setup_custom_fields(@task)
  end

  # GET /tasks/1/edit
  def edit
    setup_custom_fields(@task)
  end

  # POST /tasks or /tasks.json
  def create
    @task = Task.new(task_params)
    @task.entity_id = @task.owner ? @task.owner.entity_id : @task.entity_id || current_user.entity_id
    @task.for_entity_id ||= @task.owner.entity_id || current_user.entity_id
    @task.user = current_user

    authorize @task

    if params[:make_recurring] == "1"
      # Create the recurrence rule
      # We extract common fields to the payload
      payload = task_params.to_h.except("due_date")
      rule = TaskRecurrenceRule.create!(
        entity_id: @task.entity_id,
        task_template_payload: payload,
        rrule: "FREQ=#{params[:recurrence_pattern].upcase};INTERVAL=#{params[:recurrence_interval]}",
        start_date: @task.due_date || Time.current,
        end_date: params[:recurrence_end_date].presence
      )
      @task.task_recurrence_rule = rule
      @task.original_start_date = @task.due_date
    end

    respond_to do |format|
      if @task.save
        format.turbo_stream { render :create }
        format.html { redirect_to task_url(@task), notice: "Task was successfully created." }
        format.json { render :show, status: :created, location: @task }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @task.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /tasks/1 or /tasks/1.json
  def update
    if params[:make_recurring] == "1"
      payload = task_params.to_h.except("due_date")
      rrule = "FREQ=#{params[:recurrence_pattern].upcase};INTERVAL=#{params[:recurrence_interval]}"
      if @task.task_recurrence_rule_id.present?
        @task.task_recurrence_rule.update!(
          task_template_payload: payload,
          rrule: rrule,
          end_date: params[:recurrence_end_date].presence
        )
      else
        rule = TaskRecurrenceRule.create!(
          entity_id: @task.entity_id,
          task_template_payload: payload,
          rrule: rrule,
          start_date: @task.due_date || Time.current,
          end_date: params[:recurrence_end_date].presence
        )
        @task.task_recurrence_rule = rule
        @task.original_start_date = @task.due_date
      end
    elsif @task.task_recurrence_rule_id.present? && params[:make_recurring] != "1"
      # If they unchecked "make recurring" on an existing recurring task, we detach it
      @task.update!(task_recurrence_rule_id: nil, is_exception: true)
    end

    respond_to do |format|
      if @task.update(task_params)
        format.turbo_stream { render :update }
        format.html { redirect_to task_url(@task), notice: "Task was successfully updated." }
        format.json { render :show, status: :ok, location: @task }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @task.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /tasks/1 or /tasks/1.json
  def destroy
    @task.destroy

    respond_to do |format|
      format.html { redirect_to tasks_url, notice: "Task was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def destroy_series
    authorize @task
    if @task.task_recurrence_rule.present?
      @task.task_recurrence_rule.destroy
      notice = "Entire task series was successfully destroyed."
    else
      @task.destroy
      notice = "Task was successfully destroyed."
    end

    respond_to do |format|
      format.html { redirect_to tasks_url, notice: notice }
      format.json { head :no_content }
    end
  end

  def completed
    authorize @task
    @task.completed = !@task.completed

    partial = params[:timeline].present? ? "tasks/timeline_task" : "tasks/task"
    respond_to do |format|
      if @task.save
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            @task,
            partial: partial,
            locals: { task: @task }
          )
        end
      end
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_task
    @task = Task.find(params[:id])
    authorize @task
  end

  # Only allow a list of trusted parameters through.
  def task_params
    params.require(:task).permit(:details, :response, :entity_id, :for_entity_id, :owner_id, :owner_type,
                                 :due_date, :form_type_id, :completed, :user_id, :tags, :for_support,
                                 :assigned_to_id, :category, properties: {}, reminders_attributes: Reminder::NESTED_ATTRIBUTES)
  end
end
