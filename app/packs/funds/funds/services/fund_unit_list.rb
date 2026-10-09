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

  # Free-text search over every unit the user may see. Kept out of @q so it does not show up
  # as an editable condition in the filter panel.
  SEARCH_PREDICATE = %w[
    unit_type reason capital_commitment_folio_id
  ].join("_or_").concat("_cont").freeze

  def call(&)
    @q = FundUnit.ransack(@params[:q])
    @q.sorts = ["issue_date desc", "id desc"] if @q.sorts.empty?
    @fund_units = apply_policy_scope(@q.result, &)
    @fund_units = @fund_units.includes(:fund, capital_commitment: :investor_kyc)
    @fund_units = filter_params(
      @fund_units,
      :capital_commitment_id,
      :fund_id,
      :investor_id,
      :import_upload_id,
      :owner_id,
      :owner_type
    )

    @fund_units = apply_search(@fund_units)

    Result.new(q: @q, fund_units: @fund_units)
  end

  private

  def apply_search(relation)
    term = @params[:search].to_s.strip
    return relation if term.blank?

    relation.merge(FundUnit.ransack(SEARCH_PREDICATE => term).result)
  end
end
