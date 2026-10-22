# Service for listing and filtering Capital Distribution Payments.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# standard filters, and search refinements using Chewy index.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class CapitalDistributionPaymentList < BaseList
  Result = Struct.new(:q, :capital_distribution_payments, keyword_init: true)

  def call(&)
    @q = CapitalDistributionPayment.ransack(@params[:q])
    @capital_distribution_payments = apply_policy_scope(@q.result, &)

    # :investor - the Investing Entity column links to it for rows without a KYC
    @capital_distribution_payments = @capital_distribution_payments.includes(:entity, :fund, :capital_distribution, :capital_commitment, :investor_kyc, :investor)

    @capital_distribution_payments = filter_params(@capital_distribution_payments, :fund_id, :capital_distribution_id, :capital_commitment_id, :import_upload_id)
    refine_search

    Result.new(q: @q, capital_distribution_payments: @capital_distribution_payments)
  end

  private

  def refine_search
    return unless @params[:search] && @params[:search][:value].present?

    @capital_distribution_payments = @capital_distribution_payments.where(id: search_ids)
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{SearchHelper.sanitize_text_for_search(@params[:search][:value])}*"

    filter_terms = SearchHelper.search_access_scope_for(@current_user).map do |field, values|
      SearchHelper.es_terms_filter(field, values)
    end

    filter_terms << SearchHelper.es_terms_filter(:fund_id, @params[:fund_id])
    filter_terms << SearchHelper.es_terms_filter(:capital_distribution_id, @params[:capital_distribution_id])
    filter_terms << SearchHelper.es_terms_filter(:capital_commitment_id, @params[:capital_commitment_id])
    filter_terms.compact!

    # Here we search for all the CapitalCommitments that belong to the entity of the current user

    index_search = CapitalDistributionPaymentIndex
                   .filter(bool: { filter: filter_terms })
                   .query(
                     simple_query_string: {
                       fields: CapitalDistributionPaymentIndex::SEARCH_FIELDS,
                       query:,
                       default_operator: 'and'
                     }
                   )

    index_search.map(&:id)
  end
end
