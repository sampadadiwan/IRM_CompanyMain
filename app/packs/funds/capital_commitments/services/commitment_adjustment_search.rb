class CommitmentAdjustmentSearch
  def self.perform(commitment_adjustments, current_user, params)
    return commitment_adjustments unless params[:search] && params[:search][:value].present?

    commitment_adjustments = commitment_adjustments.where(id: search_ids(params, current_user))
    commitment_adjustments.distinct
  end

  def self.search_ids(params, current_user)
    query = "#{SearchHelper.sanitize_text_for_search(params[:search][:value])}*"
    entity_ids = [current_user.entity_id]
    CommitmentAdjustmentIndex.filter(terms: { entity_id: entity_ids })
                             .query(simple_query_string: { fields: CommitmentAdjustmentIndex::SEARCH_FIELDS, query:, default_operator: 'and' })
                             .per(1000)
                             .map(&:id)
  end
end
