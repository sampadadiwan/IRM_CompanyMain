# frozen_string_literal: true

# The Support Console: a :support user picks one of their mapped clients and asks Claude Code
# (on the support machine) why something behaves the way it does for that client.
#
# The client is in every URL (`/support_console/:entity_id`) so SupportConsolePolicy#ask? can
# authorize each request from the URL alone. Conversations are AgentChatSessions owned by the
# SupportConsoleAgent record, with the client as their chattable.
#
# @see openspec/changes/support-console/design.md (card ① Console page)
class SupportConsoleController < ApplicationController
  CONVERSATION_LIST_LIMIT = 50

  # Opening a conversation, New chat and asking reload only the "support-console-thread" Turbo
  # Frame; Turbo discards everything outside it, so skip rendering the app layout for those.
  layout -> { turbo_frame_request? ? false : "modernize" }

  after_action :verify_authorized

  # X1, X2 — the spec's wording, not the app-wide "Access Denied".
  rescue_from Pundit::NotAuthorizedError do
    redirect_to root_path, alert: "Not authorized."
  end

  # GET /support_console — the client picker.
  def index
    authorize :support_console, :index?
    # H2, E1, E7 — exactly the clients this user may pick.
    @entities = pickable_entities
  end

  # GET /support_console/:entity_id — the client's conversations, and one opened if asked.
  def show
    @entity = Entity.find(params[:entity_id])
    authorize @entity, :ask?, policy_class: SupportConsolePolicy

    @entities = pickable_entities
    @conversations = conversations_for(@entity)
    @first_questions = first_questions(@conversations)
    # X3 — a session is only found through this client and the console's agent, never by id alone.
    @session = find_session(@entity, params[:session_id]) if params[:session_id].present?
  end

  # POST /support_console/:entity_id/turns — ask a question (new conversation or follow-up).
  def create_turn
    @entity = Entity.find(params[:entity_id])
    authorize @entity, :ask?, policy_class: SupportConsolePolicy
    question = params[:question].to_s.strip
    # E29, E31 — only the two named models; anything else (or nothing) is Sonnet.
    model = SupportConsoleTurnJob::MODELS.include?(params[:model]) ? params[:model] : SupportConsoleTurnJob::DEFAULT_MODEL

    # E2, E3 — refuse empty or over-long questions before anything is stored.
    error = question_error(question)
    return redirect_back_to_conversation(params[:session_id], alert: error) if error
    return redirect_back_to_conversation(params[:session_id], alert: SupportConsoleTurnJob::UNAVAILABLE) unless SupportConsoleRelayClient.configured?

    agent = SupportConsoleAgent.record
    session = params[:session_id].present? ? find_session(@entity, params[:session_id]) : start_session(agent, @entity)

    assistant = nil
    session.with_lock do
      # E4 — one turn per conversation at a time, whatever the UI showed (double click, two tabs).
      next if running_turn(session)

      # X23 — who asked, on both messages: any support user mapped to the client may follow up in
      # another's conversation, and the job re-checks access and records lookups for the asker.
      asked_by = { "asked_by_id" => current_user.id }
      session.agent_chat_messages.create!(role: "user", content: question, channel: "web", metadata: asked_by)
      assistant = session.agent_chat_messages.create!(role: "assistant", content: "Working…", channel: "web",
                                                      metadata: asked_by.merge("turn_status" => "queued", "model" => model))
    end
    return redirect_back_to_conversation(session.id, alert: SupportConsoleTurnJob::BUSY) unless assistant

    SupportConsoleTurnJob.perform_later(assistant.id)
    redirect_to support_console_entity_path(@entity, session_id: session.id)
  end

  # DELETE /support_console/:entity_id/turns/current — stop the running turn (E9).
  def stop_turn
    @entity = Entity.find(params[:entity_id])
    authorize @entity, :ask?, policy_class: SupportConsolePolicy
    session = find_session(@entity, params[:session_id])

    stopped = nil
    session.with_lock do
      stopped = running_turn(session)
      next unless stopped

      # Close the turn here; the job's own finish leaves an already-closed turn alone.
      text = stopped.content == "Working…" ? "" : stopped.content
      stopped.update!(content: [text.presence, "Stopped."].compact.join("\n\n"),
                      metadata: (stopped.metadata || {}).merge("turn_status" => "stopped", "stop_requested" => true))
    end

    stop_on_machine(session) if stopped
    redirect_to support_console_entity_path(@entity, session_id: session.id)
  end

  QUESTION_LIMIT = 4000

  private

  # @return [String, nil] why the question is refused
  def question_error(question)
    return "Please type a question." if question.empty?

    "Questions are limited to #{QUESTION_LIMIT} characters." if question.length > QUESTION_LIMIT
  end

  # @return [AgentChatSession] a new conversation for this user and client
  def start_session(agent, entity)
    AgentChatSession.create!(support_agent: agent, analyst: current_user, chattable: entity, channel: "web", status: "active")
  end

  # Only the newest assistant message of a conversation can be in flight.
  #
  # @return [AgentChatMessage, nil]
  def running_turn(session)
    latest = session.agent_chat_messages.where(role: "assistant").order(id: :desc).first
    return unless %w[queued running].include?(latest&.metadata&.dig("turn_status"))

    # E27 — a turn a Sidekiq restart left behind (turn jobs never retry) must not block the
    # conversation until the nightly sweep: past STALE_TURN it is closed here.
    if SupportConsoleRetentionJob.stale_turn?(latest)
      latest.update!(content: SupportConsoleRetentionJob::INTERRUPTED,
                     metadata: latest.metadata.merge("turn_status" => "failed"))
      return
    end
    latest
  end

  # Asks the machine to stop; the turn is already closed here, so a failure only gets logged.
  def stop_on_machine(session)
    SupportConsoleRelayClient.new.stop("#{session.chattable_id}:#{session.id}")
  rescue SupportConsoleRelayClient::Error => e
    Rails.logger.warn("[support_console] stop failed session=#{session.id} #{e.class}: #{e.message}")
  end

  def redirect_back_to_conversation(session_id, alert:)
    redirect_to support_console_entity_path(@entity, session_id: session_id.presence), alert: alert
  end

  # @return [ActiveRecord::Relation<Entity>] the picker list, through SupportConsolePolicy::Scope
  def pickable_entities
    policy_scope(Entity, policy_scope_class: SupportConsolePolicy::Scope).order(:name)
  end

  # E21 — newest first.
  #
  # @param entity [Entity]
  # @return [ActiveRecord::Relation<AgentChatSession>]
  def conversations_for(entity)
    # Before the first question anywhere, the console's agent does not exist yet: no conversations.
    agent = SupportConsoleAgent.existing
    return AgentChatSession.none unless agent

    AgentChatSession.where(support_agent: agent, chattable: entity)
                    .includes(:analyst)
                    .order(updated_at: :desc)
                    .limit(CONVERSATION_LIST_LIMIT)
  end

  # The first question of each conversation, in one grouped query.
  #
  # @param conversations [ActiveRecord::Relation<AgentChatSession>]
  # @return [Hash{Integer => String}] session id => first question
  def first_questions(conversations)
    first_ids = AgentChatMessage.where(agent_chat_session_id: conversations.map(&:id), role: "user")
                                .group(:agent_chat_session_id).minimum(:id)
    AgentChatMessage.where(id: first_ids.values).pluck(:agent_chat_session_id, :content).to_h
  end

  # @param entity [Entity]
  # @param session_id [String]
  # @return [AgentChatSession]
  # @raise [Pundit::NotAuthorizedError] for a session of another client — refused like any other
  def find_session(entity, session_id)
    AgentChatSession.find_by(id: session_id, support_agent: SupportConsoleAgent.existing, chattable: entity) ||
      raise(Pundit::NotAuthorizedError, "conversation #{session_id} is not a #{entity.id} conversation")
  end
end
