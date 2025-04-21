class InvestmentsTool < RubyLLM::Tool
  description "Gets the investments made in the portfolio company"
  param :portfolio_company_id, desc: "The id of the portfolio_company to get the investments for"

  def execute(portfolio_company_id:)
  rescue StandardError => e
    { error: e.message }
  end
end
