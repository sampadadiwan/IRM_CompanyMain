class LlmChat
  include Langchain::DependencyHelper
  include Rails.application.routes.url_helpers

  def initialize(user:, whatsapp: false)
    @user = user
    @whatsapp = whatsapp
  end

  def get_login_link(*)
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
          "Here is the document #{document.name}. " + document.file.url
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

  def assistant(llm_chat_instance)
    @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "o1-mini" })

    normal_instructions = "You're a helpful AI assistant that can use the tools provided to respond to queries. Format the responses as html tables if required. Also format links as HTML hyperlinks in the response, do not show raw URLs in the response."

    whstsaap_instructions = "You're a helpful AI assistant that can use the tools provided to respond to queries. You will receive queries over whatsapp which will have a `[whatsapp]` prefix. In such case return format the responses by using new lines and vertical seperators to create tables."

    instructions = @whatsapp ? whstsaap_instructions : normal_instructions

    @assistant ||= Langchain::Assistant.new(
      llm: @llm,
      tools: [llm_chat_instance], # Pass the calling instance (UserLlmChat/InvestorLlmChat) as the tool
      instructions:
    )

    @assistant
  end

  def query(query_string, llm_chat_instance)
    assistant(llm_chat_instance).add_message(content: query_string)
    assistant(llm_chat_instance).run(auto_tool_execution: true)
    assistant(llm_chat_instance).messages[-1].content
  end
end
