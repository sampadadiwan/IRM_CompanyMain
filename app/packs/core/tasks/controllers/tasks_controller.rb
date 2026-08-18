class TasksController < ApplicationController
  before_action :set_task, only: %i[show edit update destroy completed update_status destroy_series]

  # Most cards the kanban board will render in one go. The board has no
  # pagination (that would split a column across pages), so this is what keeps a
  # busy deal or a firm-wide board from loading thousands of rows. The view warns
  # when the cap is hit — see @board_card_limit_reached below.
  BOARD_CARD_LIMIT = 500

  # Owner types a board heading can name. A whitelist because the value comes
  # from a URL param and gets constantized (see #board_scope_label).
  BOARD_SCOPE_TYPES = %w[Deal DealInvestor Investor User SideLetterObligation CapitalCommitment PortfolioInvestment].freeze
  after_action :verify_authorized, except: %i[index search]
  after_action :verify_policy_scoped, only: []

  # GET /tasks or /tasks.json
  def index
    @bread_crumbs = { Tasks: tasks_path }
    result = TaskList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = result.q
    @tasks = result.tasks

    @for_entity = current_user.entity

    # touch_point_id filtering itself lives in TaskList alongside the other
    # filters, but the contact it names must be one this user may see, and when
    # the contact page asks for "everything with this person"
    # (touch_point_scope=all) the owner params are only there to prefill the
    # New Task form — so they must not re-narrow the list here either.
    touch_point = authorized_touch_point
    @tasks = @tasks.none if params[:touch_point_id].present? && touch_point.blank?
    across_owners = touch_point.present? && params[:touch_point_scope] == "all"

    if params[:deal_id].present?
      # A deal scope spans the Deal and its DealInvestors, so re-applying the
      # owner filter here would collapse it to Deal-owned tasks (the list's
      # Show All / Incomplete links carry owner_type=Deal). TaskList ignores
      # those params for the same reason — authorise the deal itself instead,
      # which is what with_owner_access would otherwise have done.
      deal = Deal.find_by(id: params[:deal_id])
      authorize(deal, :show?) if deal && !current_user.company_admin?
    elsif !across_owners
      @tasks = with_owner_access(@tasks, raise_error: false)
    end

    if params[:board].present?
      prepare_board_filters
      # Kanban board renders all three columns at once — pagination would split
      # columns across pages, so cap defensively instead. Order by urgency so the
      # capped subset keeps the work that matters: most overdue first, then
      # soonest due, undated last, id as a stable tiebreak.
      #
      # `due_date IS NULL` is what pushes undated tasks down — plain
      # `ORDER BY due_date` puts NULLs FIRST in both MySQL and SQLite, which
      # floated undated tasks above genuinely overdue ones in every column (and
      # let them displace dated tasks at the cap). The expression evaluates to
      # 0/1 in both engines, so it stays portable across dev/prod and test.
      @tasks = @tasks.order(Arel.sql("(tasks.due_date IS NULL)"), :due_date, :id).limit(BOARD_CARD_LIMIT)
      # Tell the user when the cap actually bit, so a truncated board can't be
      # mistaken for the full picture. `length` loads the (already capped)
      # relation the view is about to render — no extra COUNT query, unlike size.
      @board_card_limit_reached = @tasks.length >= BOARD_CARD_LIMIT
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
        # Does the new task belong to the list this form was opened from? The
        # stream prepends a row without re-running that list's query, so one
        # created outside its scope would sit at the top looking like it belongs
        # until the next reload dropped it.
        @task_in_list_scope = task_matches_list_scope?

        # In a frame (list row / embedded tab) the stream patches the list in
        # place. Standalone /tasks/new has no list to patch and no frame around
        # the form, so the stream's replace('new_task', blank) would leave an
        # empty page — send the user to the task they just created instead.
        format.turbo_stream do
          turbo_frame_request? ? render(:create) : redirect_to(task_url(@task), notice: "Task was successfully created.")
        end
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
    # Pass the persisted owner type so an update can't silently re-own the task
    normalized_params = normalized_task_params(current_owner_type: @task.owner_type)

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
        # Does the saved task still belong to the list this form was opened
        # from? update.turbo_stream patches one row without re-running the
        # list's query, so a task that just moved out of scope (its owner
        # changed, say) would otherwise sit there until the next reload.
        @task_in_list_scope = task_matches_list_scope?
        # Same split as #create: patch the row when we're inside a frame,
        # otherwise (a full-page edit, e.g. from a board card opened in its own
        # tab) redirect — see the comment in edit.html.erb. see_other because
        # Turbo requires 303 to follow a redirect after PATCH.
        format.turbo_stream do
          if turbo_frame_request?
            render :update
          else
            redirect_to task_url(@task), notice: "Task was successfully updated.", status: :see_other
          end
        end
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
    # dom_id is captured before the destroy so the stream can name the element
    # even once the record is frozen
    element_id = ActionView::RecordIdentifier.dom_id(@task)
    @task.destroy

    respond_to do |format|
      # Deleting from a board card or a list row should take away just that
      # element, not navigate the user off the page they were working on.
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(element_id),
          turbo_stream.update("user_alert", partial: "layouts/alerts",
                                            locals: { notice: "Task was successfully destroyed." })
        ]
      end
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
      # Tell the user why the drag was rejected. Two channels on purpose:
      #   * the header drives a Bootstrap toast next to the board (the drag
      #     happens under the cursor — an alert at the top of the page is easy
      #     to miss), URL-encoded because header values must stay ASCII;
      #   * the flash still rides along via WithTurboFlash as the fallback for
      #     anything that renders the stream without reading the header.
      # The JS rolls the card back; reload so it re-renders persisted state.
      message = @task.errors.full_messages.to_sentence
      response.headers["X-Task-Board-Error"] = ERB::Util.url_encode(message)
      flash.now[:alert] = message
      @task.reload
      render turbo_stream: turbo_stream.replace(@task, partial: "tasks/board_task", locals: { task: @task }),
             status: :unprocessable_entity
    end
  end

  private

  # Filter dropdown data for the kanban board (tasks/_board.html.erb) — kept out
  # of the view so the queries live at the controller layer.
  def prepare_board_filters
    @board_assignee_options = current_user.entity.employees.order(:first_name).map { |u| [u.name, u.id] }

    # A deal board spans the Deal and every DealInvestor on it, so its
    # stakeholder filter has to select a DealInvestor. Filtering by Investor here
    # would add owner_type='Investor' on top of the deal scope — a contradiction
    # that empties the board.
    @board_deal = Deal.find_by(id: params[:deal_id], entity_id: current_user.entity_id) if params[:deal_id].present?

    if @board_deal
      @board_stakeholder_options = @board_deal.deal_investors.order(:investor_name).pluck(:investor_name, :id)
      @board_selected_deal_investor = @board_deal.deal_investors.find_by(id: params[:deal_investor_id]) if params[:deal_investor_id].present?
      # DealInvestor delegates touch_point_options to its LP, so the contact
      # filter works the same on either kind of board (see WithTouchPoint).
      @board_touch_point_owner = @board_selected_deal_investor
    else
      # Stakeholder filter value: the board's own investor_id param, or an
      # Investor owner filter carried over from the list view
      selected_id = params[:investor_id].presence ||
                    (params[:owner_type] == "Investor" ? params[:owner_id].presence : nil)
      @board_selected_investor = Investor.find_by(id: selected_id, entity_id: current_user.entity_id) if selected_id
      @board_stakeholder_options = current_user.entity.investors.order(:investor_name).pluck(:investor_name, :id)
      @board_touch_point_owner = @board_selected_investor
    end

    # tags is a comma-separated string column, so the split/uniq has to happen
    # in Ruby — acceptable, tasks is a small table
    @board_tag_options = Task.where(entity_id: current_user.entity_id).where.not(tags: [nil, ""])
                             .distinct.pluck(:tags)
                             .flat_map { |t| t.split(",") }.map(&:strip).uniq.sort

    assign_board_scope!
  end

  # What this board covers, for the heading: every board otherwise renders as a
  # bare "Tasks Board", so a deal's board, one stakeholder's board and the
  # firm-wide board are indistinguishable once you've navigated to them.
  #
  # Sets the record too, so the heading can link back to it — the board is
  # usually reached from that page and this is the way back.
  def assign_board_scope!
    @board_scope_owner, kind =
      if @board_deal
        [@board_deal, "Deal"]
      elsif params[:owner_type].present? && params[:owner_id].present? &&
            BOARD_SCOPE_TYPES.include?(params[:owner_type])
        # "DealInvestor" reads as "Deal Investor" for a business user
        [params[:owner_type].constantize.find_by(id: params[:owner_id]),
         params[:owner_type].underscore.humanize.titleize]
      elsif @board_selected_investor
        [@board_selected_investor, "Stakeholder"]
      end

    return if @board_scope_owner.blank?

    @board_scope_label = "#{kind}: #{@board_scope_owner}"
    @board_scope_path = board_scope_path(@board_scope_owner)
  end

  # nil rather than an exception when the owner has no show route (or its route
  # needs parameters we don't have) — the heading then renders as plain text.
  def board_scope_path(owner)
    polymorphic_path(owner)
  rescue NoMethodError, ActionController::UrlGenerationError
    nil
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

  # current_owner_type: the owner type already on a persisted task (nil when
  # creating). Used to protect an existing task's owner from being rewritten by a
  # form that had no option for it — see the guards below.
  def normalized_task_params(current_owner_type: nil)
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

    # Deal and DealInvestor owners are set from the deal UI; no form rendered
    # outside that context offers them, so a posted owner_type=User for such a
    # task is the browser defaulting to the first option, never a real choice.
    # Dropping both keys leaves the task attached to its deal.
    if %w[Deal DealInvestor].include?(current_owner_type) && attrs["owner_type"] == "User"
      attrs.delete("owner_type")
      attrs.delete("owner_id")
    end

    # A personal task belongs to whoever created it — but only default the owner
    # when the task is new or already personal. Applying it on update is what
    # re-owned deal tasks to the editor (and, when the editor was also the
    # assignee, made it look like the owner had been set to assigned_to).
    attrs["owner_id"] = current_user.id if attrs["owner_type"] == "User" && current_owner_type.in?([nil, "User"])

    attrs
  end

  # True when @task matches the scope of the list the form was opened from —
  # asked on create (should the new row be prepended?) and on update (should the
  # patched row stay?). The form carries that scope as hidden fields: deal_id for
  # a deal's Tasks tab, embedded_owner_id for an owner's tab,
  # list_touch_point_id for a contact's. An unscoped list — the global Tasks
  # page — contains every task, so nothing can fall out of it.
  def task_matches_list_scope?
    # A contact's tab lists only tasks with that person; a task saved without
    # them (or with someone else) does not belong there whatever its owner is.
    if params[:list_touch_point_id].present? &&
       @task.touch_point_id.to_s != params[:list_touch_point_id].to_s
      return false
    end

    if params[:deal_id].present?
      case @task.owner_type
      when "Deal" then @task.owner_id.to_s == params[:deal_id].to_s
      when "DealInvestor" then DealInvestor.exists?(id: @task.owner_id, deal_id: params[:deal_id])
      else false
      end
    elsif params[:embedded_owner_id].present?
      @task.owner_id.to_s == params[:embedded_owner_id].to_s
    else
      true
    end
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
