# frozen_string_literal: true

# One message as the chat kit draws it (ai_chat/_question, ai_chat/_answer), whichever store it came
# from: Chat/Message (Assistants, KPI chat) or AgentChatSession/AgentChatMessage (floating window,
# Support Console). View-only — never saved.
#
# @see openspec/changes/ai-chat-kit/design.md (card ② Item and row shapes)
class AiChatItem < Data.define(:dom_id, :role, :content, :time, :status, :turn_status, :progress, :model, :asker,
                               :feedback_rating, :message_id)
  # The text a placeholder answer is saved with before its first streamed chunk (Support Console).
  PLACEHOLDERS = ["Working…", "…"].freeze

  # An AgentChatMessage as an item. The Support Console's turn job passes the in-flight text and
  # metadata while an answer streams, so those override what is saved.
  #
  # @param message [AgentChatMessage]
  # @param content [String, nil] in-flight text (SupportConsoleTurnJob)
  # @param metadata [Hash, nil] in-flight metadata (SupportConsoleTurnJob)
  # @param asker [String, nil] who asked, for a question's tooltip (X23)
  # @return [AiChatItem]
  def self.from_agent_chat_message(message, content: nil, metadata: nil, asker: nil)
    metadata = (metadata || message.metadata || {}).to_h
    turn_status = metadata["turn_status"]
    # Feedback only when already loaded (the floating window preloads it); never one query per item.
    feedback = message.association(:feedback).loaded? ? message.feedback&.rating : nil
    new(dom_id: ActionView::RecordIdentifier.dom_id(message), role: message.role,
        content: content || message.content,
        # A question is timed when asked, an answer when it last changed (finished streaming).
        time: message.role == "user" ? message.created_at : message.updated_at,
        status: status_for(turn_status), turn_status:, progress: Array(metadata["progress"]),
        model: metadata["model"].presence, asker:, feedback_rating: feedback, message_id: message.id)
  end

  # A ruby_llm Message (Assistants page, KPI chat) as an item: an assistant message still without
  # content is the pending answer.
  #
  # @param message [Message]
  # @return [AiChatItem]
  def self.from_message(message)
    pending = message.role == "assistant" && message.content.blank?
    new(dom_id: ActionView::RecordIdentifier.dom_id(message), role: message.role, content: message.content,
        time: message.role == "user" ? message.created_at : message.updated_at,
        status: pending ? :running : :answered, turn_status: nil, progress: [], model: nil, asker: nil,
        feedback_rating: nil, message_id: message.id)
  end

  # @param turn_status [String, nil] metadata["turn_status"] (Support Console); nil elsewhere
  # @return [Symbol] :running, :stopped, :failed, :refused or :answered
  def self.status_for(turn_status)
    case turn_status
    when "queued", "running" then :running
    when "stopped", "failed", "refused" then turn_status.to_sym
    else :answered
    end
  end

  def question? = role == "user"

  def running? = status == :running

  # The answer's text to show and copy — nil while only a placeholder has been saved.
  #
  # @return [String, nil]
  def text
    content unless content.blank? || PLACEHOLDERS.include?(content)
  end
end
