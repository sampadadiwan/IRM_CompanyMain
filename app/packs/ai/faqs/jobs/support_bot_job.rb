class SupportBotJob < ApplicationJob
  queue_as :default

  def perform(faq_thread_id, user_message)
    faq_thread = FaqThread.find(faq_thread_id)
    SupportBotService.new(faq_thread: faq_thread).ask(user_message)
  end
end
