# frozen_string_literal: true

# One conversation in the chat kit's list (ai_chat/_conversation): its first question, who started
# it, when it last changed, its status badge (AiChatHelper::AI_CHAT_STATUS_BADGES) and its link.
#
# @see openspec/changes/ai-chat-kit/design.md (card ② Item and row shapes)
AiChatRow = Data.define(:id, :title, :starter, :updated_at, :status, :url)
