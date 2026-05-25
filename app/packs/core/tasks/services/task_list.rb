# Service for listing and filtering Tasks.
class TaskList < BaseList
  Result = Struct.new(:q, :tasks, keyword_init: true)

  def call(&)
    @q = Task.ransack(@params[:q])
    @tasks = apply_policy_scope(@q.result, &)
    @tasks = @tasks.includes(:for_entity, :user, :task_template, :assigned_to, :rich_text_details, :rich_text_response, :owner)

    # Apply standard filters
    @tasks = filter_params(@tasks, :owner_id, :owner_type, :assigned_to_id)

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

    # Apply scope filters
    @tasks = @tasks.incomplete if @params[:completed] != 'all'
    @tasks = @tasks.for_support if @params[:for_support].present? && @params[:for_support] != 'false'

    Result.new(q: @q, tasks: @tasks)
  end
end
