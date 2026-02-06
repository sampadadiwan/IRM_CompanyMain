# Service for listing and filtering Tasks.
class TaskList
  Result = Struct.new(:q, :tasks, keyword_init: true)

  def self.call(current_user, params, &)
    new(current_user, params).call(&)
  end

  def initialize(current_user, params)
    @current_user = current_user
    @params = params
  end

  def call
    @params[:q] = JSON.parse(@params[:q]) if @params[:q].is_a?(String)

    @q = Task.ransack(@params[:q])

    scope = @q.result
    scope = if block_given?
              yield(scope)
            else
              Pundit.policy_scope!(@current_user, scope)
            end

    @tasks = scope.includes(:for_entity, :user, :task_template, :assigned_to, :rich_text_details, :rich_text_response)

    filter_params(:owner_id, :owner_type, :assigned_to_id)

    apply_scopes

    Result.new(q: @q, tasks: @tasks)
  end

  private

  def filter_params(*keys)
    keys.each do |key|
      @tasks = @tasks.where(key => @params[key]) if @params[key].present?
    end
  end

  def apply_scopes
    @tasks = @tasks.incomplete if @params[:completed] != 'all'
    @tasks = @tasks.for_support if @params[:for_support].present? && @params[:for_support] != 'false'
  end
end
