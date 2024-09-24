class InvestorLlmChat
  extend Langchain::ToolDefinition
  include Langchain::DependencyHelper

  def initialize(user:, whatsapp: false)
    @service = LlmChat.new(user:, whatsapp:)
  end

  # Define Langchain tools for the assistant
  define_function :get_login_link, description: "InvestorTools: return a link by which the investor can login" do
    property :salt, type: "string", description: "random salt", required: false
  end

  define_function :show_commitments, description: "InvestorTools: Show the commitments for the given fund name" do
    property :fund_name, type: "string", description: "The name of the fund for which the commitments are to be retrieved", required: false
  end

  define_function :show_funds, description: "InvestorTools: Show the funds for the given investor" do
    property :fund_name, type: "string", description: "The name of the fund", required: false
  end

  define_function :get_document, description: "InvestorTools: Get the named document for the given fund name" do
    property :fund_name, type: "string", description: "The name of the fund", required: true
    property :document_name, type: "string", description: "The name of the document to be retrieved", required: true
  end

  def what_can_you_do(*)
    "As an Investor, you can ask me to:
    1. Get my login link
    2. Show me my fund details
    3. Show me my commitments
    4. Get a specific document for me"
  end

  # Delegating service methods to keep the code clean
  delegate :get_login_link, :show_commitments, :show_funds, :get_document, to: :@service

  def assistant
    @service.assistant(self)
  end

  def query(query_string)
    @service.query(query_string, self)
  end
end
