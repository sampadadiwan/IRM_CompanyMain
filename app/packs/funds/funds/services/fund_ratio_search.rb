class FundRatioSearch
  def self.perform(fund_ratios, current_user, params)
    fund_ratios = fund_ratios.where(id: search_ids(params, current_user)) if params[:search] && params[:search][:value].present?
    fund_ratios
  end

  def self.search_ids(params, current_user)
    # This is only when the datatable sends a search query
    query = "#{params[:search][:value]}*"
    entity_ids = [current_user.entity_id]
    FundRatioIndex.filter(terms: { entity_id: entity_ids })
                  .query(query_string: { fields: FundRatioIndex::SEARCH_FIELDS,
                                         query:, default_operator: 'and' }).per(100).map(&:id)
  end
end
