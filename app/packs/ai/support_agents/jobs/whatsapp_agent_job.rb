# frozen_string_literal: true

# Background job for processing inbound WhatsApp messages via the AI agent framework.
#
# The webhook must return 200 immediately; the LLM call can take 5–30 seconds.
# This job delegates all business logic to WhatsappChatDispatcher.
#
# @see WhatsappChatDispatcher
# @see UsersController#whatsapp_webhook
class WhatsappAgentJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 0

  # sample message received webhook from whatsapp api
  # { id: "message.Id", created: "2026-06-26T10:44:26.7174781Z", whatsappMessageId: "message.WhatsappMessageId", conversationId: "message.ConversationId", ticketId: "message.TicketId", text: "text", type: "type", data: null, sourceId: null, sourceUrl: null, timestamp: "message.Time", owner: false, eventType: "message", statusString: "statusString", avatarUrl: "message.AvatarUrl", assignedId: "message.AssignedId", operatorName: "message.OperatorName", operatorEmail: "operatorEmail", waId: "senderPhone", messageContact: null, senderName: "senderName", listReply: null, interactiveButtonReply: null, buttonReply: null, replyContextId: null, sourceType: 0, frequentlyForwarded: false, forwarded: false, controller: "users", action: "whatsapp_webhook", user: { id: "message.Id" } }

  # sample new contact message
  # { id: "message.Id", created: "2026-06-26T10:44:26.7174781Z", whatsappMessageId: "message.WhatsappMessageId", conversationId: "message.ConversationId", ticketId: "message.TicketId", text: "text", type: "type", data: null, sourceId: null, sourceUrl: null, timestamp: "message.Time", owner: false, eventType: "message", statusString: "statusString", avatarUrl: "message.AvatarUrl", assignedId: "message.AssignedId", operatorName: "message.OperatorName", operatorEmail: "operatorEmail", waId: "senderPhone", messageContact: null, senderName: "senderName", listReply: null, interactiveButtonReply: null, buttonReply: null, replyContextId: null, sourceType: 0, frequentlyForwarded: false, forwarded: false, controller: "users", action: "whatsapp_webhook", user: { id: "message.Id" } }
  def perform(params_json)
    params = JSON.parse(params_json).with_indifferent_access

    # Only handle inbound user messages; ignore sent messages and other event types
    return unless params[:eventType].to_s == "message" && params[:owner] == false

    wa_id = params[:waId].to_s
    if wa_id.length < 10
      Rails.logger.error "[WhatsApp Webhook] Invalid waId: #{wa_id}"
      return
    end

    user = User.find_by(phone: wa_id[-10..], call_code: wa_id[..-11])
    unless user
      Rails.logger.error "[WhatsApp Webhook] Unknown phone: #{wa_id}"
      return
    end

    if Entity.where(id: Investor.where(investor_entity_id: user.entity_id).pluck(:entity_id) + [user.entity_id]).where_permissions(:enable_whatsapp).exists?
      WhatsappChatDispatcher.call(
        user_id: user.id,
        message_text: params[:text].to_s,
        conversation_id: params[:conversationId].to_s
      )
    end
  end
end
