require 'langchainrb'

class UserLlmChat
  extend Langchain::ToolDefinition
  include Langchain::DependencyHelper
  include Rails.application.routes.url_helpers

  define_function :get_login_link, description: "InvestorTools: return a link by which the user can login" do
    property :salt, type: "string", description: "random salt", required: false
  end

  define_function :show_commitments, description: "InvestorTools: Show the commitments for the given fund name" do
    property :fund_name, type: "string", description: "The name of the fund for which the commitments are to be retrived", required: false
  end

  define_function :show_funds, description: "InvestorTools: Show the funds for the given investor" do
    property :fund_name, type: "string", description: "The name of the fund", required: false
  end

  define_function :get_document, description: "InvestorTools: Get the named document for the given fund name" do
    property :fund_name, type: "string", description: "The name of the fund for which the SOA is to be retrived", required: true
    property :document_name, type: "string", description: "The name of the document to be retrived", required: true
  end

  define_function :what_can_you_do, description: "InvestorTools: Return the list of things that the user can do with this assistant, or if the user asks for help" do
    property :query, type: "string", description: "The query string", required: false
  end

  def initialize(user:)
    @user = user
  end

  def what_can_you_do(query: nil)
    "You can ask me to get
    1. a login link
    2. show commitments
    3. show funds
    4. get a document"
  end

  def get_login_link(salt: nil)
    signed_id = @user.signed_id(expires_in: 5.minutes)
    no_password_login_users_url(signed_id:)
  end

  def show_commitments(fund_name: nil)
    capital_commitments = Pundit.policy_scope(@user, CapitalCommitment)
    capital_commitments = capital_commitments.joins(:fund).where("funds.name like ?", "%#{fund_name}%") if fund_name.present?
    capital_commitments.includes(:fund).map do |cc|
      {
        fund: cc.fund.name,
        committed_amount: cc.committed_amount,
        currency: cc.currency,
        date: cc.commitment_date
      }
    end
  end

  def show_funds(fund_name: nil)
    funds = Pundit.policy_scope(@user, Fund)
    funds = funds.where("funds.name like ?", "%#{fund_name}%") if fund_name.present?
    funds.includes(:entity).map do |fund|
      {
        name: fund.name,
        entity: fund.entity.name
      }
    end
  end

  def get_document(fund_name:, document_name:)
    fund = Pundit.policy_scope(@user, Fund).where(name: fund_name).first
    if fund.present?
      investor = fund.entity.investors.where(investor_entity_id: @user.entity_id).first
      if investor.present?
        document = fund.capital_commitments.where(investor_id: investor.id).first.documents.approved.where("documents.name like ?", "%#{document_name}%").order(created_at: :desc).first
        if document.present?
          "Here is the docment #{document.name}. " + document.file.url
        else
          "No SOA found for the fund #{fund_name}"
        end
      else
        "You are not an investor in the fund #{fund_name}"
      end
    else
      "No fund found with the name #{fund_name}"
    end
  end

  def assistant
    @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "o1-mini" })

    @assistant ||= Langchain::Assistant.new(
      llm: @llm,
      tools: [self],
      instructions: "You're a helpful AI assistant that can use the tools provided to respond to queries. Format the responses as html tables if required. Also format links as HTML hyperlinks in the response, do not show raw URLs in the response."
    )

    @assistant
  end

  def query(query_string)
    assistant.add_message(content: query_string)
    assistant.run(auto_tool_execution: true)
    assistant.messages[-1].content
  end
end
