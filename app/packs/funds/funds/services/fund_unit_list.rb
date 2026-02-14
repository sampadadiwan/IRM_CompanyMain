# Service for listing and filtering Fund Units.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the FundUnitsController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class FundUnitList < BaseList
  Result = Struct.new(:q, :fund_units, keyword_init: true)

  def call(&)
    @q = FundUnit.ransack(@params[:q])
    @fund_units = apply_policy_scope(@q.result, &)
    @fund_units = @fund_units.includes(:fund, :capital_commitment)
    @fund_units = filter_params(
      @fund_units,
      :capital_commitment_id,
      :fund_id,
      :investor_id,
      :import_upload_id,
      :owner_id,
      :owner_type
    )

    Result.new(q: @q, fund_units: @fund_units)
  end
end
