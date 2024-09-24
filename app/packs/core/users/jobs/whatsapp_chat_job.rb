class WhatsappChatJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 2

  def perform(user_id, query)
    send_response(user_id, query)
  end

  private

  def send_response(user_id, query)
    user = User.find(user_id)
    chat_class = user.curr_role == "Investor" ? InvestorLlmChat : UserLlmChat
    response = chat_class.new(user:, whatsapp: true).query(query)
    result = WhatsappGeneralNotification.send_session_message({ whatsapp_number: user.phone_with_call_code,
                                                                message: response })
    Rails.logger.debug result
  end
end
