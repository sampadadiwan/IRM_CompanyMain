class SoaCheckJob < ApplicationJob
  queue_as :low
  MODEL = 'gemini-2.5-flash-preview-04-17'.freeze

  def perform(capital_commitment_id, soa_name, user_id)
    Chewy.strategy(:sidekiq) do
      capital_commitment = CapitalCommitment.find(capital_commitment_id)
      user = User.find(user_id)

      chat = Chat.create(user_id: user.id, entity_id: user.entity_id, model_id: MODEL, owner: capital_commitment, name: "SOA Check")

      # Set the system message
      chat.with_instructions("You are an diligent fund operations associate working in an AIF, and can look closely at the details of the SOA and check for any discrepancies. You will generally format your analysis in tables.")

      send_notification("Analysis SOA started", user.id)
      analyze_soa(capital_commitment, soa_name, chat, user)
      send_notification("Analysis of SOA completed", user.id)
    end
  end

  IP_QUESTION = "Summarize the Investor Presentation document. In section 1 clearly outline the key facts and figures from the document in tables, In section 2 present an analysis of the key facts and strategy discussed. In section 3 generate a table of key questions based on the document that need further attention. In section 4 add a table listing the risks for the company.".freeze

  def analyze_soa(capital_commitment, soa_name, chat, _user)
    Rails.logger.debug { "Analyzing SOA #{capital_commitment.id}" }
    doc = capital_commitment.documents.where("name like '%#{soa_name}%'").first
    chat.ask(IP_QUESTION, with: { pdf: doc.file_url }) if doc.present?
  end
end
