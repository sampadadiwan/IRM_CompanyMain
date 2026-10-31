# frozen_string_literal: true

# A screen's conversation list for the chat kit: at most LIMIT rows, newest first, and whether more
# exist ("50+ conversations"). Titles and statuses come from grouped queries — a fixed number of
# queries per list, never one per row.
#
# @see openspec/changes/ai-chat-kit/design.md (card ② Item and row shapes, decision 8)
class AiChatRows < Data.define(:rows, :more)
  # The most conversations a list shows (the Support Console's cap, now every screen's).
  LIMIT = 50

  # AgentChatSession conversations (floating window, Support Console).
  #
  # @param scope [ActiveRecord::Relation<AgentChatSession>] already scoped to what the user may see
  # @param url [Proc] session -> link to open it
  # @return [AiChatRows]
  def self.for_agent_sessions(scope, url:)
    # One extra row tells whether the list was cut off.
    sessions = scope.includes(:analyst).reorder(updated_at: :desc).limit(LIMIT + 1).to_a
    shown = sessions.first(LIMIT)
    ids = shown.map(&:id)
    titles = first_contents(AgentChatMessage, :agent_chat_session_id, ids)
    statuses = latest_turn_statuses(ids)
    rows = shown.map do |session|
      # A conversation handed to a human (Customer Support) reads Escalated whatever its last turn was.
      status = session.escalated? ? "escalated" : statuses[session.id]
      AiChatRow.new(id: session.id, title: titles[session.id], starter: session.analyst&.full_name,
                    updated_at: session.updated_at, status:, url: url.call(session))
    end
    new(rows:, more: sessions.size > LIMIT)
  end

  # Chat conversations (Assistants page, KPI chat).
  #
  # @param scope [ActiveRecord::Relation<Chat>] already scoped to what the user may see
  # @param url [Proc] chat -> link to open it
  # @return [AiChatRows]
  def self.for_chats(scope, url:)
    chats = scope.includes(:user).reorder(updated_at: :desc).limit(LIMIT + 1).to_a
    shown = chats.first(LIMIT)
    titles = first_contents(Message, :chat_id, shown.map(&:id))
    rows = shown.map do |chat|
      AiChatRow.new(id: chat.id, title: titles[chat.id] || chat.name, starter: chat.user&.full_name,
                    updated_at: chat.updated_at, status: nil, url: url.call(chat))
    end
    new(rows:, more: chats.size > LIMIT)
  end

  # The first user message of each conversation: one grouped MIN(id), then one pluck.
  #
  # @return [Hash{Integer => String}] conversation id => first question
  def self.first_contents(model, key, ids)
    return {} if ids.empty?

    first_ids = model.where(key => ids, role: "user").group(key).minimum(:id)
    model.where(id: first_ids.values).pluck(key, :content).to_h
  end

  # The turn status of each session's latest answer (Support Console turns; nil elsewhere).
  #
  # @return [Hash{Integer => String, nil}] session id => turn_status
  def self.latest_turn_statuses(ids)
    return {} if ids.empty?

    last_ids = AgentChatMessage.where(agent_chat_session_id: ids, role: "assistant")
                               .group(:agent_chat_session_id).maximum(:id)
    AgentChatMessage.where(id: last_ids.values).pluck(:agent_chat_session_id, :metadata)
                    .to_h { |session_id, metadata| [session_id, metadata&.dig("turn_status")] }
  end

  delegate :empty?, to: :rows

  # "50+ conversations" when cut off, otherwise "N conversations".
  #
  # @return [String]
  def count_label
    more ? "#{LIMIT}+ conversations" : ActionController::Base.helpers.pluralize(rows.size, "conversation")
  end
end
