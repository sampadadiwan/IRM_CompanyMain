# Service for listing and filtering Investor KYCs.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# controller scopes, and KycSearch.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class InvestorKycList
  Result = Struct.new(:q, :investor_kycs, keyword_init: true)

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
    # Parse params[:q] if string (logic from controller)
    @params[:q] = JSON.parse(@params[:q]) if @params[:q].is_a?(String)

    @q = InvestorKyc.ransack(@params[:q])

    scope = @q.result
    scope = if block_given?
              yield(scope)
            else
              Pundit.policy_scope!(@current_user, scope)
            end

    @investor_kycs = scope.includes(:entity, :investor)
    @investor_kycs = @investor_kycs.includes(:support_agent_report) if @params[:support_agent_report].present?

    apply_scopes

    @investor_kycs = KycSearch.perform(@investor_kycs, @current_user, @params)

    Result.new(q: @q, investor_kycs: @investor_kycs)
  end

  private

  def apply_scopes
    # Replicating has_scope logic from controller
    @investor_kycs = @investor_kycs.uncalled if @params[:uncalled].present? && @params[:uncalled] != 'false'
    @investor_kycs = @investor_kycs.unverified if @params[:unverified].present? && @params[:unverified] != 'false'
    @investor_kycs = @investor_kycs.agreement_uncalled if @params[:agreement_uncalled].present? && @params[:agreement_uncalled] != 'false'
    @investor_kycs = @investor_kycs.agreement_overcalled if @params[:agreement_overcalled].present? && @params[:agreement_overcalled] != 'false'
  end
end
