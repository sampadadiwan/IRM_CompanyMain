class DocumentsTool < RubyLLM::Tool
  description "Gets the latest documents for the portfolio company"
  param :portfolio_company_id, desc: "The id of the portfolio_company to get the latest documents for"

  def execute(portfolio_company_id:)
  rescue StandardError => e
    { error: e.message }
  end
end
