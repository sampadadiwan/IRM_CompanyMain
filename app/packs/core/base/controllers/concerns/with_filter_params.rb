module WithFilterParams
  extend ActiveSupport::Concern

  # This method is used to perform a Ransack search on the model associated with the current controller,
  # apply policy scope, and optionally filter the results to include only records with snapshots.
  #
  # @return [ActiveRecord::Relation] The scoped query result after applying Ransack search, policy scope,
  #   and optional snapshot filtering.
  #
  # The method performs the following steps:
  # 1. Determines the model class associated with the current controller.
  # 2. Initializes a Ransack search object using the `params[:q]` query parameters.
  # 3. Applies the policy scope to the Ransack search result.
  # 4. If the `params[:snapshot]` parameter is present, further filters the results to include records with snapshots also.
  def ransack_with_snapshot
    # Get the current controllers model class
    model_class = controller_name.classify.constantize
    # If snapshot is present, we need to return records with_snapshots
    model_class = model_class.with_snapshots if params[:snapshot].present?
    # Get the ransack search object
    @q = model_class.ransack(params[:q])
    # Create the scope for the model
    policy_scope(@q.result)
  end

  def filter_params(scope, *keys)
    keys.each do |key|
      scope = scope.where(key => params[key]) if params[key].present?
    end
    scope
  end

  def filter_range(scope, column, start_date:, end_date:)
    return scope unless start_date.present? || end_date.present?

    if start_date.present? && end_date.present?
      scope.where(column => start_date..end_date)
    elsif start_date.present?
      scope.where("#{column} >= ?", start_date)
    else # end_date.present?
      scope.where("#{column} <= ?", end_date)
    end
  end
end
