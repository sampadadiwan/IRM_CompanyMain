class PortfolioInvestmentSearch
  def self.perform(portfolio_investments, current_user, params)
    portfolio_investments = portfolio_investments.where(id: search_ids(params, current_user)) if params[:search] && params[:search][:value].present?
    portfolio_investments.distinct
  end

  def self.search_ids(params, current_user)
    query = "#{params[:search][:value]}*"
    entity_ids = [current_user.entity_id]
    PortfolioInvestmentIndex.filter(terms: { entity_id: entity_ids })
                            .query(query_string: { fields: PortfolioInvestmentIndex::SEARCH_FIELDS,
                                                   query:, default_operator: 'and' }).per(1000).map(&:id)
  end
end
