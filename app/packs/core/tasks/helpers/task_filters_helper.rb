# frozen_string_literal: true

# Option data for the tasks filter bar (tasks/_filter_bar.html.erb), which the
# list view (tasks/_index) and the kanban board (tasks/_board) share.
#
# This lives in a helper rather than in TasksController because the list partial
# is rendered straight from other controllers too — a side letter's covenant
# tasks, an obligation's tasks tab, an event's tasks tab — and those would
# otherwise render the bar with no options in it. Nothing here runs unless the
# bar is actually rendered, so the views that render none (search results, the
# timeline, the JSON build) pay for none of these queries.
#
# `filter_params` throughout is the scope the bar is filtering within, as a
# string-keyed Hash: the request params, plus what the host page passed the list
# partial as locals (see _filter_bar's `scope`). Those locals matter — on a side
# letter's page the whole task scope arrives that way and the request params
# describe the side letter, not the tasks.
module TaskFiltersHelper
  Options = Struct.new(:deal, :assignees, :stakeholders, :stakeholder_search, :selected_investor,
                       :selected_deal_investor, :touch_point_owner, :tags, :categories,
                       keyword_init: true)

  # The only frame ids a tasks response can contain: tasks/index.html.erb wraps
  # itself in "tasks_frame" and tasks/_index in "task_list". A host page's frame
  # has to be named one of these or Turbo finds no match in the response and the
  # frame fails to load at all — which is why several pages render duplicate
  # "tasks_frame" elements rather than scoping them per record, and why the
  # filter bar's controller resolves its frame by walking up from the form
  # instead of by id. Also a whitelist because the value arrives as a request
  # header and is written into a DOM attribute.
  FRAMES = %w[tasks_frame task_list].freeze

  # Which Turbo frame a filter submit should refresh.
  #
  # Every frame the list lives in is declared `target: "_top"` — that is what
  # makes a row's links open the task's own page, and equally what makes a form
  # inside one reload the whole page unless it names a frame itself.
  def task_filter_turbo_frame
    # An embedded tab loaded the list into a frame the host page named —
    # "tasks_frame" on a deal or document tab, "task_list" on a stakeholder or
    # commitment tab — and Turbo sends that id back as a header on every request
    # that frame makes, this form's submits included. Refreshing it in place is
    # what keeps the tab from reloading the page around it.
    return turbo_frame_request_id if FRAMES.include?(turbo_frame_request_id)

    # A list rendered straight from another controller (a side letter's covenant
    # tasks, an event's tasks) has no frame request behind it, but it is embedded
    # all the same — tasks/_index always wraps itself in "task_list".
    return "task_list" unless controller_name == "tasks"

    # The standalone /tasks page (list or board). Its stat cards sit outside
    # every frame and are computed from the same filters, so a frame-only swap
    # would leave them contradicting the list underneath.
    "_top"
  end

  # Not memoized: the bar renders once per page, and a memo keyed on nothing
  # would hand a second list on the same page the first one's scope.
  def task_filter_options(filter_params)
    entity = current_user.entity
    options = Options.new(assignees: entity.employees.order(:first_name).map { |u| [u.name, u.id] })

    # A deal scope spans the Deal and every DealInvestor on it, so its
    # stakeholder filter has to select a DealInvestor. Filtering by Investor here
    # would add owner_type='Investor' on top of the deal scope — a contradiction
    # that empties the list.
    options.deal = Deal.find_by(id: filter_params["deal_id"], entity_id: entity.id) if filter_params["deal_id"].present?

    if options.deal
      options.stakeholders = options.deal.deal_investors.order(:investor_name).pluck(:investor_name, :id)
      if filter_params["deal_investor_id"].present?
        options.selected_deal_investor = options.deal.deal_investors.find_by(id: filter_params["deal_investor_id"])
      end
      # DealInvestor delegates touch_point_options to its LP, so the contact
      # filter works the same under either kind of scope (see WithTouchPoint).
      options.touch_point_owner = options.selected_deal_investor
    else
      # Stakeholder filter value: the bar's own investor_id, or an Investor owner
      # filter carried over from the list view.
      selected_id = filter_params["investor_id"].presence ||
                    (filter_params["owner_type"] == "Investor" ? filter_params["owner_id"].presence : nil)
      options.selected_investor = Investor.find_by(id: selected_id, entity_id: entity.id) if selected_id
      # A flag, not a list. This scope is not pinned to a record, so the options
      # would be every investor in the tenant — thousands of rows plucked and
      # inlined as <option>s on the firm-wide list and the dashboard widget, on
      # every render. The view renders a typeahead instead, sourced from
      # InvestorsController#search, which is bounded per keystroke.
      options.stakeholder_search = task_stakeholder_filter?(filter_params)
      # Contacts come from the stakeholder in the select, or — on a tab that
      # already is one — from the scoped record itself, so an LP's or a deal
      # investor's own tasks tab can be narrowed to one person with no
      # stakeholder select to pick from first.
      options.touch_point_owner = options.selected_investor || task_filter_deal_investor(filter_params)
    end

    # tags is a comma-separated string column, so the split/uniq has to happen
    # in Ruby — acceptable, tasks is a small table.
    tags = Task.where(entity_id: entity.id).where.not(tags: [nil, ""])
               .distinct.pluck(:tags)
               .flat_map { |t| t.split(",") }.map(&:strip).uniq.sort

    # Category isn't an enum — Task::CATEGORIES is only the form's default list,
    # and the "Other" free-text fallback means real data can hold values outside
    # it. Offer what is actually in use (SQL-deduped, per the hygiene rules)
    # rather than categories no task in this tenant carries.
    categories = Task.where(entity_id: entity.id).where.not(category: [nil, ""])
                     .distinct.order(:category).pluck(:category)

    # A filter already applied has to stay selectable even when nothing in use
    # matches it — a sidebar link naming a category no task carries yet, say —
    # or the select renders blank while the list is still filtered by it.
    options.tags = task_filter_keep_selected(tags, filter_query["tags_cont"])
    options.categories = task_filter_keep_selected(categories, filter_query["category_eq"])
    options
  end

  # params[:q] as a plain Hash. Some links (the stat cards) pass it JSON-encoded
  # rather than as nested params, so neither params.dig(:q, ...) nor
  # params[:q][...] is safe on it — both raise on a String.
  def filter_query
    params[:q].to_unsafe_h
  rescue StandardError
    {}
  end

  # Does this scope leave room for a stakeholder filter? A list already pinned to
  # one record — an obligation, a document, a KPI report — has its stakeholder
  # fixed by that scope, and TaskList ignores investor_id whenever owner_id is
  # set, so the select would be a dead control there. Side letter covenant tasks
  # span many obligation owners of one side letter, same story. The board is the
  # exception for an Investor owner: it is reached by an explicit "Board" link
  # and the select is how you switch stakeholder on it (the filter bar drops the
  # owner pin to match).
  def task_stakeholder_filter?(filter_params)
    return false if filter_params["side_letter_id"].present?
    return true if filter_params["owner_id"].blank?

    filter_params["board"].present? && filter_params["owner_type"] == "Investor"
  end

  private

  # The deal investor a list is scoped to, for the contact select. `for` joins
  # investors on investor_entity_id, so this cannot reach another tenant's row.
  def task_filter_deal_investor(filter_params)
    return unless filter_params["owner_type"] == "DealInvestor" && filter_params["owner_id"].present?

    DealInvestor.for(current_user).find_by(id: filter_params["owner_id"])
  end

  def task_filter_keep_selected(options, selected)
    return options if selected.blank? || options.include?(selected)

    (options + [selected]).sort
  end
end
