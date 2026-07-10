class LlmChat
  include Langchain::DependencyHelper
  include Rails.application.routes.url_helpers

  def initialize(user:, whatsapp: false)
    @user = user
    @whatsapp = whatsapp
  end

  def get_login_link(*)
    # Self-login link delivered over WhatsApp. This is a legitimate self-service channel: the
    # WhatsApp agent resolves @user from the SENDER's own registered phone number
    # (WhatsappAgentJob: User.find_by(phone:, call_code:)), so the link can only ever reach the
    # account owner — the same trust model as an email magic link.
    #
    # Short 2-minute TTL (finding H3): the URL is produced as an LLM tool result and therefore
    # transits the LLM provider and the WhatsApp channel, so we keep the replay window minimal.
    # SECURITY (finding M1): dedicated purpose (matched in no_password_login) so this token can
    # never be interchanged with any other User signed_id.
    signed_id = @user.signed_id(expires_in: 2.minute, purpose: User::MAGIC_LINK_PURPOSE)
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
          "No Investor Statement found for the fund #{fund_name}"
        end
      else
        "You are not an investor in the fund #{fund_name}"
      end
    else
      "No fund found with the name #{fund_name}"
    end
  end

  NORMAL_INSTRUCTIONS = "You're a helpful AI assistant that can use the tools provided to respond to queries. Format the responses as html tables if required. Also format links as HTML hyperlinks in the response, do not show raw URLs in the response.".freeze

  WHATSAPP_INSTRUCTIONS = "You're a helpful AI assistant that can use the tools provided to respond to queries. You will receive queries over whatsapp which will have a `[whatsapp]` prefix. In such case return format the responses by using new lines and vertical seperators to create tables.".freeze

  def assistant(llm_chat_instance)
    @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"], llm_options: { model: "o1-mini" })

    instructions = @whatsapp ? WHATSAPP_INSTRUCTIONS : NORMAL_INSTRUCTIONS

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
