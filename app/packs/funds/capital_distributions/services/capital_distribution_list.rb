# Service for listing and filtering Capital Distributions.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the CapitalDistributionsController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class CapitalDistributionList < BaseList
  Result = Struct.new(:q, :capital_distributions, keyword_init: true)

  def call(&)
    @q = CapitalDistribution.ransack(@params[:q])
    @capital_distributions = apply_policy_scope(@q.result, &)
    @capital_distributions = @capital_distributions.includes(:fund, :entity)
    @capital_distributions = filter_params(@capital_distributions, :fund_id, :import_upload_id)

    Result.new(q: @q, capital_distributions: @capital_distributions)
  end
end
