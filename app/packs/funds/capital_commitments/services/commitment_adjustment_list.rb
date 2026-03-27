# Service for listing and filtering Commitment Adjustments.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the CommitmentAdjustmentsController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class CommitmentAdjustmentList < BaseList
  Result = Struct.new(:q, :commitment_adjustments, keyword_init: true)

  def call(&)
    @q = CommitmentAdjustment.ransack(@params[:q])
    @commitment_adjustments = apply_policy_scope(@q.result, &)
    @commitment_adjustments = @commitment_adjustments.includes(:fund, :capital_commitment)

    # ElasticSearch
    @commitment_adjustments = CommitmentAdjustmentSearch.perform(@commitment_adjustments, @current_user, @params)

    # Apply standard filters
    @commitment_adjustments = filter_params(@commitment_adjustments, :capital_commitment_id, :fund_id)

    # Grouped DataFrame response (adhoc pivot or aggregation)
    Result.new(
      q: @q,
      commitment_adjustments: @commitment_adjustments
    )
  end
end
