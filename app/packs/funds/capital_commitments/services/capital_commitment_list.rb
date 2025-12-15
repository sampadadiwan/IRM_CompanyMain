# Service for listing and filtering Capital Commitments.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the CapitalCommitmentsController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class CapitalCommitmentList
  Result = Struct.new(:q, :capital_commitments, :data_frame, :adhoc_json, :template, keyword_init: true)

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
    @q = CapitalCommitment.ransack(@params[:q])
    @capital_commitments = if block_given?
                             yield(@q.result)
                           else
                             Pundit.policy_scope!(@current_user, @q.result)
                           end
    @capital_commitments = @capital_commitments.includes(:entity, :fund, :investor_kyc, :investor)

    # Step 2: Special filter for DataTables search
    @capital_commitments = @capital_commitments.where(id: search_ids) if @params.dig(:search, :value).present?

    @capital_commitments = @capital_commitments.where(id: @params[:capital_commitment_ids]) if @params[:capital_commitment_ids].present?

    # Step 3: Standard filters
    filter_params(
      :fund_id,
      :investor_id,
      :import_upload_id,
      :onboarding_completed
    )

    # Step 4: Grouped DataFrame response (adhoc pivot or aggregation)
    template = "index"
    if @params[:group_fields].present?
      @data_frame = CapitalCommitmentDf.new.df(@capital_commitments, @current_user, @params)
      @adhoc_json = @data_frame.to_a.to_json
      template = @params[:template].presence || "index"
    end

    Result.new(
      q: @q,
      capital_commitments: @capital_commitments,
      data_frame: @data_frame,
      adhoc_json: @adhoc_json,
      template: template
    )
  end

  private

  def filter_params(*keys)
    keys.each do |key|
      @capital_commitments = @capital_commitments.where(key => @params[key]) if @params[key].present?
    end
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{SearchHelper.sanitize_text_for_search(@params[:search][:value])}*"
    term = { entity_id: @current_user.entity_id }

    # Here we search for all the CapitalCommitments that belong to the entity of the current user
    # Only return first 100 results
    index_search = CapitalCommitmentIndex.filter(term:)
                                         .query(simple_query_string: { fields: CapitalCommitmentIndex::SEARCH_FIELDS,
                                                                       query:, default_operator: 'and' })

    index_search = index_search.filter(term: { fund_id: @params[:fund_id] }) if @params[:fund_id].present?
    index_search = index_search.per(100)

    index_search.map(&:id)
  end
end
