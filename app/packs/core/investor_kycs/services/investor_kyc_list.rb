# Service for listing and filtering Investor KYCs.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# controller scopes, and KycSearch.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class InvestorKycList < BaseList
  include HasScope

  has_scope :uncalled, type: :boolean
  has_scope :unverified, type: :boolean
  has_scope :agreement_uncalled, type: :boolean
  has_scope :agreement_overcalled, type: :boolean

  Result = Struct.new(:q, :investor_kycs, keyword_init: true)

  def call(&)
    translate_json_fields_params(InvestorKyc)
    @q = InvestorKyc.ransack(@params[:q])
    @investor_kycs = apply_policy_scope(@q.result, &)

    @investor_kycs = @investor_kycs.includes(:entity, :investor)
    @investor_kycs = @investor_kycs.includes(:support_agent_report) if @params[:support_agent_report].present?

    @investor_kycs = apply_scopes(@investor_kycs, @params)
    @investor_kycs = KycSearch.perform(@investor_kycs, @current_user, @params)

    Result.new(q: @q, investor_kycs: @investor_kycs)
  end
end
