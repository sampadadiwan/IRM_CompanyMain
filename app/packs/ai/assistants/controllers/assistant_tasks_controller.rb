class AssistantTasksController < ApplicationController
  before_action :set_assistant_task, only: %i[show edit update destroy]

  def index
    @assistant_tasks = policy_scope(AssistantTask).order(created_at: :desc)
    authorize AssistantTask
  end

  def show
    authorize @assistant_task
  end

  def new
    @assistant_task = AssistantTask.new(user: current_user, entity: current_user.entity)
    authorize @assistant_task
  end

  def edit
    authorize @assistant_task
  end

  def create
    @assistant_task = AssistantTask.new(assistant_task_params)
    @assistant_task.user = current_user
    @assistant_task.entity = current_user.entity
    authorize @assistant_task

    if @assistant_task.save
      redirect_to @assistant_task, notice: 'Assistant task was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    authorize @assistant_task
    if @assistant_task.update(assistant_task_params)
      redirect_to @assistant_task, notice: 'Assistant task was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @assistant_task
    @assistant_task.destroy
    redirect_to assistant_tasks_url, notice: 'Assistant task was successfully destroyed.'
  end

  private

  def set_assistant_task
    @assistant_task = AssistantTask.find(params[:id])
  end

  def assistant_task_params
    params.require(:assistant_task).permit(:assistant_type, :assistant_metadata, :period, :tag_list, :instructions)
  end
end
