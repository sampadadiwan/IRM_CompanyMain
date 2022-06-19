class TasksController < ApplicationController
  before_action :set_task, only: %i[show edit update destroy completed]
  after_action :verify_authorized, except: %i[index search]

  # GET /tasks or /tasks.json
  def index
    @tasks = policy_scope(Task)
    @tasks = @tasks.where(completed: false) if params[:completed].blank?
    @tasks = @tasks.includes(:investor, :user).page(params[:page])
  end

  def search
    query = params[:query]
    if query.present?
      @tasks = TaskIndex.filter(term: { entity_id: current_user.entity_id })
                        .query(query_string: { fields: TaskIndex::SEARCH_FIELDS,
                                               query:, default_operator: 'and' }).page(params[:page]).objects

      render "index"
    else
      redirect_to tasks_path(request.parameters)
    end
  end

  # GET /tasks/1 or /tasks/1.json
  def show; end

  # GET /tasks/new
  def new
    @task = Task.new
    @task.entity_id = current_user.entity_id
    @task.user = current_user
    authorize @task
  end

  # GET /tasks/1/edit
  def edit; end

  # POST /tasks or /tasks.json
  def create
    @task = Task.new(task_params)
    @task.entity_id = current_user.entity_id
    @task.user = current_user

    authorize @task

    respond_to do |format|
      if @task.save
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

    respond_to do |format|
      if @task.save
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(@task)
          ]
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
    params.require(:task).permit(:details, :entity_id, :investor_id, :filter_id, :completed, :user_id)
  end
end
