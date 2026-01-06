# Service for listing and filtering Capital Remittances.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the CapitalRemittancesController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class CapitalRemittanceList
  Result = Struct.new(:q, :capital_remittances, :capital_call, :capital_commitment, keyword_init: true)

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
    # Step 1: Apply Ransack search and policy scope
    @q = CapitalRemittance.ransack(@params[:q])
    @capital_remittances = if block_given?
                             yield(@q.result)
                           else
                             Pundit.policy_scope!(@current_user, @q.result)
                           end
    @capital_remittances = @capital_remittances.includes(:fund, :investor, :capital_call, :entity, capital_commitment: :fund)

    # Step 2: Special filter for DataTables search
    @capital_remittances = @capital_remittances.where(id: search_ids) if @params.dig(:search, :value).present?

    # Step 3: Standard filters
    filter_params(
      :fund_id,
      :capital_call_id,
      :capital_commitment_id,
      :import_upload_id
    )

    @capital_remittances = @capital_remittances.where(status: @params[:status].split(",")) if @params[:status].present?
    @capital_remittances = @capital_remittances.where(verified: @params[:verified] == "true") if @params[:verified].present?

    capital_call = CapitalCall.find(@params[:capital_call_id]) if @params[:capital_call_id].present?
    capital_commitment = CapitalCommitment.find(@params[:capital_commitment_id]) if @params[:capital_commitment_id].present?

    Result.new(
      q: @q,
      capital_remittances: @capital_remittances,
      capital_call: capital_call,
      capital_commitment: capital_commitment
    )
  end

  private

  def filter_params(*keys)
    keys.each do |key|
      @capital_remittances = @capital_remittances.where(key => @params[key]) if @params[key].present?
    end
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{@params[:search][:value]}*"
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
