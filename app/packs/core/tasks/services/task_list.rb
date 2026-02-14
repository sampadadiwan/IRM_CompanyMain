# Service for listing and filtering Tasks.
class TaskList < BaseList
  Result = Struct.new(:q, :tasks, keyword_init: true)

  def call(&)
    @q = Task.ransack(@params[:q])
    @tasks = apply_policy_scope(@q.result, &)
    @tasks = @tasks.includes(:for_entity, :user, :task_template, :assigned_to, :rich_text_details, :rich_text_response)

    # Apply standard filters
    @tasks = filter_params(@tasks, :owner_id, :owner_type, :assigned_to_id)

    # Apply scope filters
    @tasks = @tasks.incomplete if @params[:completed] != 'all'
    @tasks = @tasks.for_support if @params[:for_support].present? && @params[:for_support] != 'false'

    Result.new(q: @q, tasks: @tasks)
  end
end
