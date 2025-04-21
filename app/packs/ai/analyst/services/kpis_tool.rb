class KpisTool < RubyLLM::Tool
  description "Gets the latest kpis for the portfolio company"
  param :portfolio_company_id, desc: "The id of the portfolio_company to get the latest kpis for"

  def execute(portfolio_company_id:)
  rescue StandardError => e
    { error: e.message }
  end
end
