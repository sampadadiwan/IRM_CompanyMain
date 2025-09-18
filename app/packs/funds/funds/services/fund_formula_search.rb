class FundFormulaSearch
  def self.perform(fund_formulas, current_user, params)
    fund_formulas = fund_formulas.where(id: search_ids(params, current_user)) if params[:search] && params[:search][:value].present?
    fund_formulas
  end

  def self.search_ids(params, current_user)
    # This is only when the datatable sends a search query
    query = "#{params[:search][:value]}*"
    entity_ids = [current_user.entity_id]
    FundFormulaIndex.filter(terms: { entity_id: entity_ids })
                    .query(query_string: { fields: FundFormulaIndex::SEARCH_FIELDS,
                                           query:, default_operator: 'and' }).per(1000).map(&:id)
  end
end
