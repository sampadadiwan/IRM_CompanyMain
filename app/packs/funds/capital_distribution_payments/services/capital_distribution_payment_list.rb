# Service for listing and filtering Capital Distribution Payments.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# standard filters, and search refinements using Chewy index.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class CapitalDistributionPaymentList
  Result = Struct.new(:q, :capital_distribution_payments, keyword_init: true)

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
    initialize_query
    apply_scope { |relation| block_given? ? yield(relation) : relation }
    filter_additional_params
    refine_search

    Result.new(q: @q, capital_distribution_payments: @capital_distribution_payments)
  end

  private

  def initialize_query
    @q = CapitalDistributionPayment.ransack(@params[:q])
  end

  def apply_scope
    scope = @q.result
    scope = if block_given?
              yield(scope)
            else
              Pundit.policy_scope!(@current_user, scope)
            end

    @capital_distribution_payments = scope.includes(:entity, :fund, :capital_distribution, :capital_commitment, :investor_kyc)
  end

  def filter_additional_params
    @capital_distribution_payments = @capital_distribution_payments.where(fund_id: @params[:fund_id]) if @params[:fund_id].present?
    @capital_distribution_payments = @capital_distribution_payments.where(capital_distribution_id: @params[:capital_distribution_id]) if @params[:capital_distribution_id].present?
    @capital_distribution_payments = @capital_distribution_payments.where(capital_commitment_id: @params[:capital_commitment_id]) if @params[:capital_commitment_id].present?
    @capital_distribution_payments = @capital_distribution_payments.where(import_upload_id: @params[:import_upload_id]) if @params[:import_upload_id].present?
  end

  def refine_search
    return unless @params[:search] && @params[:search][:value].present?

    @capital_distribution_payments = @capital_distribution_payments.where(id: search_ids)
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{@params[:search][:value]}*"
    term = { entity_id: @current_user.entity_id }

    # Here we search for all the CapitalCommitments that belong to the entity of the current user

    index_search = CapitalDistributionPaymentIndex.filter(term:)
                                                  .query(simple_query_string: { fields: CapitalDistributionPaymentIndex::SEARCH_FIELDS,
                                                                                query:, default_operator: 'and' })

    # Filter by fund, capital_distribution and capital_commitment
    index_search = index_search.filter(term: { fund_id: @params[:fund_id] }) if @params[:fund_id].present?
    index_search = index_search.filter(term: { capital_distribution_id: @params[:capital_distribution_id] }) if @params[:capital_distribution_id].present?
    index_search = index_search.filter(term: { capital_commitment_id: @params[:capital_commitment_id] }) if @params[:capital_commitment_id].present?

    index_search.map(&:id)
  end
end
