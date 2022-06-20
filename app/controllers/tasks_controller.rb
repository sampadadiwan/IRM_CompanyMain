class TasksController < ApplicationController
  before_action :set_task, only: %i[show edit update destroy completed]
  after_action :verify_authorized, except: %i[index search]
  after_action :verify_policy_scoped, only: []

  # GET /tasks or /tasks.json
  def index
    @for_entity = current_user.entity
    if params[:owner_id].present? && params[:owner_type].present?
      # This is the tasks for a specific owen like interest/offer/deal etc
      @owner = params[:owner_type].constantize.find(params[:owner_id])
      if policy(@owner).show?
        @tasks = Task.where(owner_id: params[:owner_id])
        @tasks = @tasks.where(owner_type: params[:owner_type])
      end
    elsif params[:entity_id].present?
      # This is the tasks for a specific entity, usually by investor
      @tasks = Task.where(entity_id: params[:entity_id], for_entity_id: current_user.entity_id)
    elsif params[:for_entity_id].present?
      # This is to see all tasks under investors task tab
      @for_entity = Entity.find(params[:for_entity_id])
      @tasks = Task.where(entity_id: current_user.entity_id, for_entity_id: params[:for_entity_id])
    else
      @tasks = policy_scope(Task)
    end

    @tasks = @tasks.where(completed: false) if params[:completed].blank?
    # Hack to filter by for_entity_id for documents
    @tasks = @tasks.where(for_entity_id: params[:for_entity_id]) if params[:for_entity_id].present?

    @tasks = @tasks.includes(:for_entity, :user).page(params[:page])
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
    @task = params[:task] ? Task.new(task_params) : Task.new
    @task.entity_id ||= current_user.entity_id
    @task.user = current_user
    authorize @task
  end

  # GET /tasks/1/edit
  def edit; end

  # POST /tasks or /tasks.json
  def create
    @task = Task.new(task_params)
    @task.entity_id = @task.owner ? @task.owner.entity_id : current_user.entity_id
    @task.for_entity_id ||= current_user.entity_id
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
    params.require(:task).permit(:details, :entity_id, :for_entity_id, :owner_id, :owner_type, :completed, :user_id)
  end
end
