class AnalystBase
  DEFAULT_INSTRUCTIONS = <<~INSTRUCTIONS.freeze
    You are an amazing financial analyst working in an AIF, and can analyze portfolio company data to produce beautiful and comprehensive analyst reports.
  INSTRUCTIONS

  def initialize(portfolio_company_id, model: 'gemini-2.5-pro-exp-03-25',
                 temperature: 0.4, instructions: DEFAULT_INSTRUCTIONS)
    @portfolio_company_id = portfolio_company_id
    @portfolio_company = Investor.find(portfolio_company_id)
    @chat = RubyLLM.chat(model:)
    @chat.with_instructions(instructions)
    @report = {}
  end

  def plan
    instructions = "Please create a simple plan for the analysis of the portfolio company #{@portfolio_company.investor_name}. The plan should be the sections and sub sections, with brief description of each section and sub section. Return this in json format only like plan: [ {section_name: 'Name of the section', description: 'The description', sub_sections: [{name: 'Name of the sub section', description: 'description of the sub section'}] } ], and no additional info or text"
    @report[:plan] = @chat.ask(instructions)
  end

  def research; end
end
