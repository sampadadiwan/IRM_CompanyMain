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
    @tasks = filter_params(@tasks, :owner_id, :owner_type, :assigned_to_id, :touch_point_id)

    # Special handling for Deal-related tasks to include both the Deal and its Investors
    if @params[:deal_id].present?
      deal = Deal.find_by(id: @params[:deal_id])
      if deal
        investor_ids = deal.deal_investors.pluck(:id)
        @tasks = @tasks.where(
          "(owner_id = ? AND owner_type = 'Deal') OR (owner_id IN (?) AND owner_type = 'DealInvestor')",
          deal.id, investor_ids.presence || [0]
        ).includes(:owner)
      end
    end

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

  # Backward compatibility: some callers still pass investor_id instead of owner_id/owner_type.
  def normalize_owner_filters!
    return unless @params[:owner_id].blank? && @params[:investor_id].present?

    @params[:owner_id] = @params[:investor_id]
    @params[:owner_type] ||= "Investor"
  end
end
