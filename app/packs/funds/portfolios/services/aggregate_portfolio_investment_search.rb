class AggregatePortfolioInvestmentSearch
  def self.perform(aggregate_portfolio_investments, current_user, params)
    aggregate_portfolio_investments = aggregate_portfolio_investments.where(id: search_ids(params, current_user)) if params[:search] && params[:search][:value].present?
    aggregate_portfolio_investments.distinct
  end

  def self.search_ids(params, current_user)
    query = "#{SearchHelper.sanitize_text_for_search(params[:search][:value])}*"

    filter_terms = SearchHelper.search_access_scope_for(current_user).map do |field, values|
      SearchHelper.es_terms_filter(field, values)
    end
    filter_terms.compact!

    AggregatePortfolioInvestmentIndex.filter(bool: { filter: filter_terms })
                                     .query(simple_query_string: {
                                              fields: AggregatePortfolioInvestmentIndex::SEARCH_FIELDS,
                                              query:,
                                              default_operator: 'and'
                                            }).per(1000).map(&:id)
  end
end
