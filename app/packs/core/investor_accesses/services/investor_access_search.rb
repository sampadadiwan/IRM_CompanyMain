class InvestorAccessSearch
  def self.perform(investor_accesses, current_user, params)
    investor_accesses = investor_accesses.where(id: search_ids(params, current_user)) if params[:search] && params[:search][:value].present?
    investor_accesses.distinct
  end

  def self.search_ids(params, current_user)
    query = "#{params[:search][:value]}*"
    entity_ids = [current_user.entity_id]

    InvestorAccessIndex.filter(terms: { entity_id: entity_ids })
                       .query(query_string: { fields: InvestorAccessIndex::SEARCH_FIELDS, query:, default_operator: 'and' })
                       .per(1000)
                       .map(&:id)
  end
end
