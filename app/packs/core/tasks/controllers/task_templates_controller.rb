class TaskTemplatesController < ApplicationController
  before_action :set_task_template, only: %i[show edit update destroy]

  # GET /task_templates
  def index
    @q = TaskTemplate.ransack(params[:q])
    @task_templates = policy_scope(@q.result)

    @task_templates = @task_templates.order(:for_class, position: :asc) if params[:sort].blank?
    @pagy, @task_templates = pagy(@task_templates)
  end

  def generate
    @model = params[:for_class].constantize.find(params[:for_class_id])
    authorize @model, :update?
    @model.generate_next_steps(tag_list: params[:tag_list], save_step: true)
  end

  # GET /task_templates/1
  def show; end

  # GET /task_templates/new
  def new
    @task_template = TaskTemplate.new
    authorize @task_template
  end

  # GET /task_templates/1/edit
  def edit; end

  # POST /task_templates
  def create
    @task_template = TaskTemplate.new(task_template_params)
    authorize @task_template
    if @task_template.save
      redirect_to @task_template, notice: "Task template was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /task_templates/1
  def update
    if @task_template.update(task_template_params)
      redirect_to @task_template, notice: "Task template was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /task_templates/1
  def destroy
    @task_template.destroy!
    redirect_to task_templates_url, notice: "Task template was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_task_template
    @task_template = TaskTemplate.find(params[:id])
    authorize @task_template

    @bread_crumbs = { Templates: task_templates_path,
                      "#{@task_template}": task_template_path(@task_template) }
  end

  # Only allow a list of trusted parameters through.
  def task_template_params
    params.require(:task_template).permit(:details, :for_class, :tag_list, :due_in_days, :action_link, :help_link, :position, :entity_id)
  end
end
