class AccountEntrySearch
  class << self
    def perform(account_entries, current_user, params)
      account_entries = account_entries.where(id: search_ids(params, current_user)) if params[:search] && params[:search][:value].present?
      account_entries.distinct
    end

    def search_ids(params, current_user)
      query = "#{params[:search][:value]}*"
      entity_ids = [current_user.entity_id]

      search_results = AccountEntryIndex.filter(terms: { entity_id: entity_ids }).query(query_string: { fields: AccountEntryIndex::SEARCH_FIELDS, query:, default_operator: 'and' })

      search_results = search_results.filter(term: { fund_id: params[:fund_id] }) if params[:fund_id].present?
      search_results = search_results.filter(term: { capital_commitment_id: params[:capital_commitment_id] }) if params[:capital_commitment_id].present?

      search_results.per(1000).map(&:id)
    end
  end
end
