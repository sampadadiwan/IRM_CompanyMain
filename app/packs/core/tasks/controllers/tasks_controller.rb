class TasksController < ApplicationController
  before_action :set_task, only: %i[show edit update destroy completed]
  after_action :verify_authorized, except: %i[index search]
  after_action :verify_policy_scoped, only: []

  # GET /tasks or /tasks.json
  def index
    authorize(Task)
    @tasks = policy_scope(Task)
    @for_entity = params[:for_entity_id].present? ? Entity.find(params[:for_entity_id]) : current_user.entity

    @tasks = with_owner_access(@tasks, raise_error: false)

    @tasks = filter_params(@tasks, :completed, :for_support, :entity_id, :for_entity_id, :assigned_to_id, :owner_id, :owner_type)

    @tasks = @tasks.includes(:for_entity, :user, :task_template).page(params[:page])
  end

  def search
    @search = true
    query = params[:query]
    if query.present?
      @tasks = TaskIndex.filter(term: { entity_id: current_user.entity_id })
                        .or(TaskIndex.filter(term: { for_entity_id: current_user.entity_id })
                      .query(query_string: { fields: TaskIndex::SEARCH_FIELDS,
                                             query:, default_operator: 'and' }).page(params[:page]))

      @tasks = @tasks.page(params[:page]).objects
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
                                 :assigned_to_id, properties: {}, reminders_attributes: Reminder::NESTED_ATTRIBUTES)
  end
end
