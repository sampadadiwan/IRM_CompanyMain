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
    @capital_remittances = @capital_remittances.includes(:fund, :investor, :capital_call, :entity, :capital_remittance_payments, :investor_kyc, capital_commitment: %i[fund investor_kyc])

    # Special filter for DataTables search
    @capital_remittances = @capital_remittances.where(id: search_ids) if @params.dig(:search, :value).present?

    # Apply standard filters
    @capital_remittances = filter_params(@capital_remittances, :fund_id, :capital_call_id, :capital_commitment_id, :import_upload_id)

    # Custom filters for status and verified (comma-separated and boolean)
    @capital_remittances = @capital_remittances.where(status: @params[:status].split(",")) if @params[:status].present?
    @capital_remittances = @capital_remittances.where(verified: @params[:verified] == "true") if @params[:verified].present?
    @capital_remittances = @capital_remittances.collected_amount_positive if enforce_collected_amount_positive?
    @capital_remittances = @capital_remittances.where(id: @params[:capital_remittance_ids]) if @params[:capital_remittance_ids].present?

    Result.new(
      q: @q,
      capital_remittances: @capital_remittances,
      capital_call: find_capital_call,
      capital_commitment: find_capital_commitment
    )
  end

  private

  # The capital-call bulk-verify modal always sends collected_amount_positive=true, but
  # that's a client-supplied flag — a hand-crafted request to bulk_actions could omit it
  # and re-enqueue verification of $0-collected remittances, the exact bug this filter
  # exists to prevent. So enforce it server-side whenever the request shape matches that
  # bulk-verify path (bulk_action=Verify, verified=false, scoped to a capital_call),
  # regardless of what the client actually sent. The separate "Toggle Verify" bulk action
  # (verified/unverified toggle over search results, no capital_call_id) is unaffected.
  def enforce_collected_amount_positive?
    return true if @params[:collected_amount_positive] == "true"

    @params[:bulk_action].to_s.casecmp("verify").zero? &&
      @params[:verified] == "false" &&
      @params[:capital_call_id].present?
  end

  def find_capital_call
    CapitalCall.find(@params[:capital_call_id]) if @params[:capital_call_id].present?
  end

  def find_capital_commitment
    CapitalCommitment.find(@params[:capital_commitment_id]) if @params[:capital_commitment_id].present?
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{SearchHelper.sanitize_text_for_search(@params[:search][:value])}*"

    filter_terms = SearchHelper.search_access_scope_for(@current_user).map do |field, values|
      SearchHelper.es_terms_filter(field, values)
    end

    filter_terms << SearchHelper.es_terms_filter(:fund_id, @params[:fund_id])
    filter_terms << SearchHelper.es_terms_filter(:capital_call_id, @params[:capital_call_id])
    filter_terms << SearchHelper.es_terms_filter(:capital_commitment_id, @params[:capital_commitment_id])
    filter_terms.compact!

    # Here we search for all the CapitalCommitments that belong to the entity accesible to current user
    # Only return first 100 results
    index_search = CapitalRemittanceIndex
                   .filter(bool: { filter: filter_terms })
                   .query(
                     simple_query_string: {
                       fields: CapitalRemittanceIndex::SEARCH_FIELDS,
                       query:,
                       default_operator: 'and'
                     }
                   )
                   .per(100)

    index_search.map(&:id)
  end
end
