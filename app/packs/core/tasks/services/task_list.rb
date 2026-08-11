# Service for listing and filtering Tasks.
class TaskList < BaseList
  Result = Struct.new(:q, :tasks, keyword_init: true)

  # How far back the kanban board's Done column reaches — keeps the board
  # bounded instead of loading every completed task the tenant ever created.
  BOARD_DONE_WINDOW = 30.days

  def call(&)
    normalize_owner_filters!

    @q = Task.ransack(@params[:q])
    @tasks = apply_policy_scope(@q.result, &)
    # Preload only what each view renders (CLAUDE.md: no speculative eager
    # loading). Board cards use details/owner/assigned_to/touch_point; the list
    # additionally renders for_entity, user, template and response.
    # :touch_point covers the "With" column in the tasks list (LP CRM).
    preloads = %i[assigned_to owner touch_point rich_text_details]
    preloads += %i[for_entity user task_template rich_text_response] if @params[:board].blank?
    @tasks = @tasks.includes(*preloads)

    # Apply standard filters. touch_point_id: "everything with this person" —
    # the contact's InvestorAccess id (LP CRM), same as the notes index filter.
    #
    # The contact show page sends touch_point_scope=all, meaning span owner types:
    # tasks on the LP record AND tasks logged under one of its deal investors.
    # owner_id/owner_type stay on the URL so the "New Task" button keeps
    # defaulting to the LP record — they just stop narrowing the list here.
    # TasksController authorises the contact and skips with_owner_access to match.
    #
    # A deal scope supersedes them outright: the list's Show All / Incomplete
    # links carry owner_id/owner_type=Deal alongside deal_id, and ANDing those
    # with the union below collapses it to Deal-owned tasks only — every
    # DealInvestor task silently disappears (usually leaving an empty list).
    owner_filters = skip_owner_filters? ? [] : %i[owner_id owner_type]
    @tasks = filter_params(@tasks, *owner_filters, :assigned_to_id, :touch_point_id)

    # Side letter covenant tasks span MULTIPLE SideLetterObligation owners, so a
    # single owner_id can't express "this side letter" — same cross-owner shape
    # as the Deal filter below. Used by the side letter show page's tasks tab
    # (list and board views).
    if @params[:side_letter_id].present?
      obligation_ids = SideLetterObligation.where(side_letter_id: @params[:side_letter_id]).select(:id)
      @tasks = @tasks.where(owner_type: "SideLetterObligation", owner_id: obligation_ids)
    end

    # Deal scope: the whole task set for a deal — tasks owned by the Deal itself
    # AND tasks owned by every DealInvestor on it. Drives both the deal's Tasks
    # tab and its kanban board.
    #
    # The investor side is a subquery (select(:id)), not a pluck: a deal with
    # hundreds of investors would otherwise round-trip every id through Ruby and
    # inline them into the SQL (CLAUDE.md — dedup/filter in SQL, not Ruby).
    # :owner is already preloaded above, so no extra includes here.
    if @params[:deal_id].present?
      deal = Deal.find_by(id: @params[:deal_id])
      if deal
        @tasks = @tasks.where(owner_type: "Deal", owner_id: deal.id)
                       .or(@tasks.where(owner_type: "DealInvestor", owner_id: deal.deal_investors.select(:id)))
      end
    end

    # Board filter: narrow a deal board to one investor on that deal. A separate
    # param from investor_id on purpose — that one maps to owner_type=Investor
    # (normalize_owner_filters!), which would contradict the deal scope above and
    # empty the board.
    @tasks = @tasks.where(owner_type: "DealInvestor", owner_id: @params[:deal_investor_id]) if @params[:deal_investor_id].present?

    # Support filtering by multiple owner types (e.g., Deal and DealInvestor)
    @tasks = @tasks.where(owner_type: @params[:owner_type_in]) if @params[:owner_type_in].present?

    # Apply scope filters. The kanban board needs Done tasks too, but bounded to
    # a recent window so years of history can't crowd out active cards.
    if @params[:board].present?
      @tasks = @tasks.incomplete.or(@tasks.where(completed_on: BOARD_DONE_WINDOW.ago.to_date..))
    elsif @params[:completed] != 'all'
      @tasks = @tasks.incomplete
    end
    @tasks = @tasks.for_support if @params[:for_support].present? && @params[:for_support] != 'false'

    Result.new(q: @q, tasks: @tasks)
  end

  private

  # Both cases where a broader scope owns the query and a single owner_id /
  # owner_type pair would wrongly narrow it: a deal (Deal + its DealInvestors)
  # and a contact's full history (touch_point_scope=all).
  def skip_owner_filters?
    @params[:deal_id].present? || across_owners?
  end

  # LP CRM: true when the caller wants every task involving this contact,
  # whichever record it was logged against (see the filter comment above).
  def across_owners?
    @params[:touch_point_id].present? && @params[:touch_point_scope] == "all"
  end

  # Backward compatibility: some callers still pass investor_id instead of owner_id/owner_type.
  def normalize_owner_filters!
    return unless @params[:owner_id].blank? && @params[:investor_id].present?

    @params[:owner_id] = @params[:investor_id]
    @params[:owner_type] ||= "Investor"
  end
end
