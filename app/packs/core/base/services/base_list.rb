# Base class for list services that encapsulates common patterns:
# - Ransack search with automatic JSON parsing (handled in initialize)
# - Pundit policy scoping with block support
# - Standard parameter filtering via filter_params helper
#
# Subclasses should:
# 1. Override #call to implement specific listing logic
# 2. Use helper methods: apply_policy_scope, filter_params
#
# @example
#   class MyModelList < BaseList
#     Result = Struct.new(:q, :records, keyword_init: true)
#
#     def call(&block)
#       @q = MyModel.ransack(@params[:q])
#       @records = apply_policy_scope(@q.result, &block)
#       @records = filter_params(@records, :status, :active)
#       Result.new(q: @q, records: @records)
#     end
#   end
class BaseList
  include WithFilterParams

  attr_accessor :current_user, :params

  # @param current_user [User] The user performing the action.
  # @param params [Hash] The parameters for filtering and search.
  # @yield [relation] Optional block for applying policy scope.
  def self.call(current_user, params, &)
    new(current_user, params).call(&)
  end

  def initialize(current_user, params)
    @current_user = current_user
    @params = params
    parse_ransack_params
  end

  private

  # Parses params[:q] from JSON string if needed (common for AJAX requests)
  def parse_ransack_params
    return unless @params[:q].is_a?(String)

    @params[:q] = JSON.parse(@params[:q])
  rescue JSON::ParserError => e
    Rails.logger.warn("Invalid JSON in params[:q]: #{e.message}")
    @params[:q] = {}
  end

  # Applies Pundit policy scope to a relation.
  # If a block is given, yields to it (allowing controllers to use policy_scope helper).
  # Otherwise, uses Pundit.policy_scope! directly.
  #
  # @param scope [ActiveRecord::Relation] The relation to scope.
  # @yield [scope] Optional block for custom policy scoping.
  # @return [ActiveRecord::Relation] The scoped relation.
  def apply_policy_scope(scope, &block)
    if block
      yield(scope)
    else
      Pundit.policy_scope!(@current_user, scope)
    end
  end
end
