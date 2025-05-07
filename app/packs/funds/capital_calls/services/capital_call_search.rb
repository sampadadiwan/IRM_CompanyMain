class CapitalCallSearch
  def self.perform(capital_calls, current_user, params)
    capital_calls = capital_calls.where(id: search_ids(params, current_user)) if params[:search] && params[:search][:value].present?

    capital_calls = capital_calls.where(fund_id: params[:fund_id]) if params[:fund_id].present?

    capital_calls = capital_calls.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id]
    capital_calls
  end

  def self.search_ids(params, current_user)
    # This is only when the datatable sends a search query
    query = "#{params[:search][:value]}*"
    entity_ids = [current_user.entity_id]
    CapitalCallIndex.filter(terms: { entity_id: entity_ids })
                    .query(query_string: { fields: CapitalCallIndex::SEARCH_FIELDS,
                                           query:, default_operator: 'and' }).per(100).map(&:id)
  end
end
