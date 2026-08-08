class TasksController < ApplicationController
  before_action :set_task, only: %i[show edit update destroy completed update_status destroy_series]
  after_action :verify_authorized, except: %i[index search]
  after_action :verify_policy_scoped, only: []

  # GET /tasks or /tasks.json
  def index
    @bread_crumbs = { Tasks: tasks_path }
    result = TaskList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = result.q
    @tasks = result.tasks

    @for_entity = current_user.entity
    @tasks = with_owner_access(@tasks, raise_error: false)
    # touch_point_id filtering now lives in TaskList alongside the other filters

    if params[:board].present?
      prepare_board_filters
      # Kanban board renders all three columns at once — pagination would split
      # columns across pages, so cap defensively instead. The order makes the
      # capped subset deterministic (soonest due first) rather than DB-arbitrary.
      @tasks = @tasks.order(:due_date, :id).limit(500)
    else
      @pagy, @tasks = pagy(@tasks)
    end
  end

  # Aggregated view for all Deal and DealInvestor tasks.
  # This provides a centralized dashboard for tracking deal progress across the pipeline.
  def deal_tasks
    authorize Task
    params[:owner_type_in] = %w[Deal DealInvestor]
    index
    render :index
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
  def show
    @bread_crumbs = { Tasks: tasks_path }
    @bread_crumbs[@task.owner.to_s] = polymorphic_path(@task.owner) if @task.owner.present?
    @bread_crumbs[@task.category.to_s] = task_path(@task)
  end

  # GET /tasks/new
  def new
    # Here we add owner_type and owner_id for task creation
    # embedded context is for special requirements for tasks in deal context
    @task = params[:task] ? Task.new(normalized_task_params) : Task.new
    @task.owner_id ||= params[:owner_id]
    @task.owner_type ||= params[:owner_type]
    @task.owner_type ||= "User" if params[:embedded_task_context].blank?
    @task.owner_type = "Investor" if @task.owner_id.present? && @task.owner_type.blank?
    @task.for_entity_id ||= current_user.entity_id
    @task.entity_id ||= current_user.entity_id
    @task.due_date = Time.zone.today + 1.week
    @task.user = current_user

    @bread_crumbs = { Tasks: tasks_path }
    @bread_crumbs[@task.owner.to_s] = polymorphic_path(@task.owner) if @task.owner.present?
    @bread_crumbs[:New] = nil

    authorize @task
    authorize_embedded_task_owner!(@task)
    setup_custom_fields(@task)
  end

  # GET /tasks/1/edit
  def edit
    @bread_crumbs = { Tasks: tasks_path }
    @bread_crumbs[@task.owner.to_s] = polymorphic_path(@task.owner) if @task.owner.present?
    @bread_crumbs[@task.category.to_s] = task_path(@task)
    @bread_crumbs[:Edit] = nil

    setup_custom_fields(@task)
  end

  # POST /tasks or /tasks.json
  def create
    normalized_params = normalized_task_params
    @task = Task.new(normalized_params)
    @task.owner_type = "Investor" if @task.owner_id.present? && @task.owner_type.blank?
    @task.entity_id ||= current_user.entity_id
    @task.for_entity_id ||= current_user.entity_id
    @task.user = current_user

    authorize @task
    authorize_embedded_task_owner!(@task)

    setup_doc_user(@task)

    if params[:make_recurring] == "1"
      # Create the recurrence rule
      # We extract common fields to the payload
      payload = normalized_params.except("due_date")
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
    normalized_params = normalized_task_params

    if params[:make_recurring] == "1"
      payload = normalized_params.except("due_date")
      rrule = "FREQ=#{params[:recurrence_pattern].upcase};INTERVAL=#{params[:recurrence_interval]}"
      if @task.task_recurrence_rule.present?
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

    setup_doc_user(@task)

    respond_to do |format|
      if @task.update(normalized_params)
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
      rule = @task.task_recurrence_rule
      tasks = rule.tasks.to_a
      ActiveRecord::Associations::Preloader.new(
        records: tasks,
        associations: %i[documents folders reminders noticed_events]
      ).call
      rule.destroy
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

  # PATCH /tasks/1/update_status — kanban board drag & drop. Re-renders the card
  # via turbo_stream so status-dependent bits (Delayed badge, completed state
  # after the Task#sync_status_and_completed callback) stay fresh.
  def update_status
    authorize @task
    # Guard before assigning: an unknown enum value raises ArgumentError
    return head :unprocessable_entity unless Task.statuses.key?(params[:status])

    @task.status = params[:status]
    @task.send_notification_flag = false # a drag is not an assignment; don't email
    if @task.save
      render turbo_stream: turbo_stream.replace(@task, partial: "tasks/board_task", locals: { task: @task })
    else
      # Tell the user why the drag was rejected — WithTurboFlash appends this
      # flash to the turbo_stream response; the JS rolls the card back and
      # renders the stream. Reload so the card re-renders persisted state.
      flash.now[:alert] = @task.errors.full_messages.to_sentence
      @task.reload
      render turbo_stream: turbo_stream.replace(@task, partial: "tasks/board_task", locals: { task: @task }),
             status: :unprocessable_entity
    end
  end

  private

  # Filter dropdown data for the kanban board (tasks/_board.html.erb) — kept out
  # of the view so the queries live at the controller layer.
  def prepare_board_filters
    # Stakeholder filter value: the board's own investor_id param, or an
    # Investor owner filter carried over from the list view
    selected_id = params[:investor_id].presence ||
                  (params[:owner_type] == "Investor" ? params[:owner_id].presence : nil)
    @board_selected_investor = Investor.find_by(id: selected_id, entity_id: current_user.entity_id) if selected_id
    @board_assignee_options = current_user.entity.employees.order(:first_name).map { |u| [u.name, u.id] }
    @board_stakeholder_options = current_user.entity.investors.order(:investor_name).pluck(:investor_name, :id)
    # tags is a comma-separated string column, so the split/uniq has to happen
    # in Ruby — acceptable, tasks is a small table
    @board_tag_options = Task.where(entity_id: current_user.entity_id).where.not(tags: [nil, ""])
                             .distinct.pluck(:tags)
                             .flat_map { |t| t.split(",") }.map(&:strip).uniq.sort
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_task
    @task = Task.find(params[:id])
    authorize @task
  end

  # Only allow a list of trusted parameters through.
  def task_params
    # touch_point_id: LP CRM — the contact's User at the LP this task involves (optional)
    params.require(:task).permit(:details, :response, :owner_id, :owner_type,
                                 :due_date, :form_type_id, :completed, :user_id, :tags, :for_support,
                                 :assigned_to_id, :category, :touch_point_id, properties: {},
                                                                              reminders_attributes: Reminder::NESTED_ATTRIBUTES,
                                                                              documents_attributes: Document::NESTED_ATTRIBUTES)
  end

  def normalized_task_params
    attrs = task_params.to_h
    # Here we set up params based on the context in which the new Task form is loaded and set the fields accordingly
    case params[:embedded_task_context].presence
    when "deal_tab"
      attrs["owner_type"] = "DealInvestor"
    when "deal_investor_tab"
      attrs["owner_type"] = "DealInvestor"
      locked_owner_id = params[:embedded_owner_id].presence || params[:owner_id].presence || attrs["owner_id"]
      attrs["owner_id"] = locked_owner_id if locked_owner_id.present?
    end

    attrs["owner_id"] = current_user.id if attrs["owner_type"] == "User"

    attrs
  end

  def authorize_embedded_task_owner!(task)
    return unless embedded_task_context?
    # Only require owner to be set and authorized when actually saving, not on form load
    return if task.new_record? && task.owner_id.blank?
    raise Pundit::NotAuthorizedError if task.owner.blank?
    raise Pundit::NotAuthorizedError unless Pundit.policy!(current_user, task.owner).update?
  end

  def embedded_task_context?
    %w[deal_tab deal_investor_tab].include?(params[:embedded_task_context].presence)
  end
end
