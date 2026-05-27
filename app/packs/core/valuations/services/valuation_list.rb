# Service for listing and filtering Valuations.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the ValuationsController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class ValuationList < BaseList
  ALLOWED_OWNER_TYPES = %w[Entity Fund Investor InvestmentInstrument].freeze

  Result = Struct.new(:q, :valuations, :owner, keyword_init: true)

  def call(&)
    translate_json_fields_params(Valuation)
    @q = Valuation.with_synthetic.ransack(@params[:q])
    @valuations = apply_policy_scope(@q.result, &)

    # Apply polymorphic owner filter
    if @params[:owner_id].present? && @params[:owner_type].present?
      raise ArgumentError, "Invalid owner_type" unless ALLOWED_OWNER_TYPES.include?(@params[:owner_type])

      @owner = @params[:owner_type].constantize.find(@params[:owner_id])
      @valuations = @valuations.where(owner: @owner)
    end

    @valuations = @valuations.includes(:entity, :investment_instrument, :owner)
    @valuations = filter_params(@valuations, :import_upload_id)

    Result.new(q: @q, valuations: @valuations, owner: @owner)
  end
end
