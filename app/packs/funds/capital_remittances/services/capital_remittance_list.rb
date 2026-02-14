# Service for listing and filtering Capital Remittances.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the CapitalRemittancesController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class CapitalRemittanceList < BaseList
  Result = Struct.new(:q, :capital_remittances, :capital_call, :capital_commitment, keyword_init: true)

  def call(&)
    @q = CapitalRemittance.ransack(@params[:q])
    @capital_remittances = apply_policy_scope(@q.result, &)
    @capital_remittances = @capital_remittances.includes(:fund, :investor, :capital_call, :entity, capital_commitment: :fund)

    # Special filter for DataTables search
    @capital_remittances = @capital_remittances.where(id: search_ids) if @params.dig(:search, :value).present?

    # Apply standard filters
    @capital_remittances = filter_params(@capital_remittances, :fund_id, :capital_call_id, :capital_commitment_id, :import_upload_id)

    # Custom filters for status and verified (comma-separated and boolean)
    @capital_remittances = @capital_remittances.where(status: @params[:status].split(",")) if @params[:status].present?
    @capital_remittances = @capital_remittances.where(verified: @params[:verified] == "true") if @params[:verified].present?

    Result.new(
      q: @q,
      capital_remittances: @capital_remittances,
      capital_call: find_capital_call,
      capital_commitment: find_capital_commitment
    )
  end

  private

  def find_capital_call
    CapitalCall.find(@params[:capital_call_id]) if @params[:capital_call_id].present?
  end

  def find_capital_commitment
    CapitalCommitment.find(@params[:capital_commitment_id]) if @params[:capital_commitment_id].present?
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{SearchHelper.sanitize_text_for_search(@params[:search][:value])}*"
    term = { entity_id: @current_user.entity_id }

    # Here we search for all the CapitalCommitments that belong to the entity of the current user
    # Only return first 100 results
    index_search = CapitalRemittanceIndex.filter(term:)
                                         .query(simple_query_string: { fields: CapitalRemittanceIndex::SEARCH_FIELDS,
                                                                       query:, default_operator: 'and' }).per(100)

    # Filter by fund, capital_distribution and capital_commitment
    index_search = index_search.filter(term: { fund_id: @params[:fund_id] }) if @params[:fund_id].present?
    index_search = index_search.filter(term: { capital_call_id: @params[:capital_call_id] }) if @params[:capital_call_id].present?
    index_search = index_search.filter(term: { capital_commitment_id: @params[:capital_commitment_id] }) if @params[:capital_commitment_id].present?
    index_search.map(&:id)
  end
end
