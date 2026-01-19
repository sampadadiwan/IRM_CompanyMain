# Service for listing and filtering Valuations.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the ValuationsController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class ValuationList
  Result = Struct.new(:q, :valuations, :owner, keyword_init: true)

  # @param current_user [User] The user performing the action.
  # @param params [Hash] The parameters for filtering and search.
  # @yield [relation] Optional block for applying policy scope.
  def self.call(current_user, params, &)
    new(current_user, params).call(&)
  end

  def initialize(current_user, params)
    @current_user = current_user
    @params = params
  end

  def call
    @q = Valuation.with_synthetic.ransack(@params[:q])

    # 1. Establish the Authorized Scope FIRST to ensure security
    scope = if block_given?
              yield(@q.result)
            else
              Pundit.policy_scope!(@current_user, @q.result)
            end

    # 2. Apply Filters to the authorized scope
    if @params[:owner_id].present? && @params[:owner_type].present?
      @owner = Object.const_get(@params[:owner_type]).find(@params[:owner_id])
      scope = scope.where(owner: @owner)
    end

    @valuations = scope.includes(:entity, :investment_instrument, :owner)

    filter_params(:import_upload_id)

    Result.new(q: @q, valuations: @valuations, owner: @owner)
  end

  private

  def filter_params(*keys)
    keys.each do |key|
      @valuations = @valuations.where(key => @params[key]) if @params[key].present?
    end
  end
end
