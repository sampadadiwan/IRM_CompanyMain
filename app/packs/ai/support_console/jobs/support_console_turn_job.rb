# frozen_string_literal: true

# Runs one Support Console turn: re-checks access, sends the question to the relay on the
# support machine, and turns the streamed events into the assistant message, query records and
# Turbo broadcasts.
#
# The assistant message is created by SupportConsoleController#create_turn with
# metadata["turn_status"] = "queued"; this job moves it to running and then to exactly one of
# completed / stopped / failed / refused (design Part 2 Lifecycles).
#
# @see openspec/changes/archive/2026-10-22-support-console/design.md (card ③ Turn job)
class SupportConsoleTurnJob < ApplicationJob
  queue_as :support_console
  # A retried turn would re-run the whole investigation; the user asks again instead.
  sidekiq_options retry: 0
  discard_on ActiveRecord::RecordNotFound

  # The models a support user can pick (design decision 9); the relay maps each name to an id.
  MODELS = %w[sonnet opus].freeze
  DEFAULT_MODEL = "sonnet"

  BROADCAST_EVERY = 5
  LAG_WARNING_SECONDS = 60

  UNAVAILABLE = "The Support Console is unavailable right now. Try again in a few minutes."
  BUSY = "Already working on a question in this conversation."
  TOO_LONG = "That took too long. Try a narrower question."
  USAGE_LIMIT = "The Support Console has reached its usage limit. Try again later."
  STARTING_MACHINE = "Starting the support machine (about 2 minutes)"

  # X28 — the Claude subscription's usage limit: expected, so the user is told and nobody is alerted.
  class UsageLimit < StandardError; end

  # @param assistant_message_id [Integer]
  def perform(assistant_message_id)
    @message = AgentChatMessage.find(assistant_message_id)
    @session = @message.agent_chat_session
    @entity = @session.chattable
    @user = asker

    # Duplicate delivery: only a queued turn may start.
    return unless claim_turn

    # E8, X23 — the asker's mapping may have changed since the question was queued. The asker, not the
    # conversation's starter: another support user may have asked this follow-up.
    return finish("refused", "Your support access to #{@entity.name} has ended.") unless @user && SupportConsolePolicy.new(@user, @entity).ask?

    run_turn
  rescue SupportConsoleRelayClient::Busy
    finish("failed", BUSY) # E11
  rescue UsageLimit => e
    log_failure(e)
    finish("failed", USAGE_LIMIT)
  rescue SupportConsoleRelayClient::Timeout => e
    # X7 — stop the machine side too, then tell the user.
    stop_quietly
    log_failure(e)
    finish("failed", TOO_LONG)
  rescue SupportConsoleRelayClient::Unavailable => e
    # X4, X5 — the machine cannot be reached or failed.
    report(e)
    finish("failed", UNAVAILABLE)
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    report(e)
    finish("failed", UNAVAILABLE) if @message
  end

  private

  # Moves the message from queued to running under its lock.
  #
  # @return [Boolean] whether this job owns the turn
  def claim_turn
    @message.with_lock do
      next false unless turn_status == "queued"

      # X26 — the stale-turn rule measures from here, not from when the question was queued.
      update_metadata("turn_status" => "running", "started_at" => Time.current.iso8601)
      true
    end
  end

  # Posts the turn and consumes the event stream until the result arrives.
  def run_turn
    request = {
      session_key: session_key,
      entity_id: @entity.id,
      question: question,
      resume_id: resume_id,
      brief: SupportConsoleClientBrief.call(@entity),
      # E30 — the name chosen in the composer, never a raw model id.
      model: MODELS.include?(@message.metadata&.dig("model")) ? @message.metadata["model"] : DEFAULT_MODEL
    }

    @text = +""
    @progress = []
    @chunks = 0
    @result = nil

    begin
      SupportConsoleRelayClient.new.post_turn(request) { |event| handle(event) }
    rescue SupportConsoleRelayClient::Unavailable
      # H9 — a stopped machine is started by the question, once, and only before anything streamed
      raise if @woken || @result || @progress.any? || @text.present? || !wake_machine

      @woken = true
      retry
    end

    # H1 — a turn that ended with a result is complete. A stream that ends without one was
    # cut off (E9 Stop, which has already closed the message, or a machine failure).
    return finish("failed", UNAVAILABLE) unless @result

    finish("completed")
  end

  # H9 — starts a stopped machine (or waits for one already starting) and waits for its relay.
  #
  # @return [Boolean] whether the relay answers now
  def wake_machine
    state = SupportConsoleMachineControl.instance&.state&.name
    return false unless %w[stopped pending running].include?(state)
    # E36 — up and answering /health: the failure is something else (X5), so no wait and no second send
    return false if state == "running" && SupportConsoleMachineControl.healthy?

    SupportConsoleMachineControl.start!(user: @user, reason: "question") if state == "stopped"
    @progress << STARTING_MACHINE
    broadcast
    SupportConsoleMachineControl.broadcast_status
    SupportConsoleMachineControl.wait_until_healthy.tap { SupportConsoleMachineControl.broadcast_status }
  end

  # Applies one relay event.
  #
  # @param event [Hash]
  def handle(event)
    case event["type"]
    when "progress"
      @progress << event["text"].to_s
      broadcast
    when "text"
      @text << event["delta"].to_s
      @chunks += 1
      broadcast if (@chunks % BROADCAST_EVERY).zero?
    when "session"
      record_claude_session(event["claude_session_id"])
    when "query"
      record_query(event)
    when "result"
      @result = event
    when "error"
      raise UsageLimit, event["message"].to_s if event["code"] == "usage_limit"
      # X29 — the subscription token is dead: reported (via Unavailable) with what to do about it.
      if event["code"] == "auth_failed"
        raise SupportConsoleRelayClient::Unavailable,
              "auth_failed: #{event['message']} — renew the Claude token: claude setup-token, then " \
              "EXECUTE=1 rake \"support_console:claude_token[<env>]\""
      end

      # X11, X12 — not a replica / replica unreachable: the machine cannot answer.
      raise SupportConsoleRelayClient::Unavailable, "#{event['code']}: #{event['message']}"
    end
  end

  # H5 — every lookup the machine attempted becomes a SupportConsoleQuery row; flagged rows alert
  # super users (E15, X10), and a re-read event is not recorded twice (X14).
  #
  # @param event [Hash]
  def record_query(event)
    SupportConsoleQuery.record_event!(event, message: @message, user: @user)
  rescue ActiveRecord::RecordInvalid => e
    # The investigation goes on; the missing audit row is reported rather than silently lost.
    ErrorReport.notify(e, job: self, query_event: event.slice("seq", "outcome", "reason"), entity_id: @entity&.id,
                          agent_chat_message_id: @message&.id)
  end

  # X25 — the Claude Code session id, stored as soon as the machine sends it: a turn that is then
  # stopped, times out or fails never reaches the result, and retention can only delete transcripts
  # whose ids it knows. Under the lock (which reloads), so a Stop written meanwhile is kept.
  #
  # @param claude_session_id [String, nil]
  def record_claude_session(claude_session_id)
    return if claude_session_id.blank?

    @message.with_lock { update_metadata("claude_session_id" => claude_session_id) }
  end

  # Writes the final state once, under the message lock, and broadcasts it.
  #
  # @param status [String] completed | stopped | failed | refused
  # @param notice [String, nil] text appended to the answer
  def finish(status, notice = nil)
    closed = false
    @message.with_lock do
      # E9 — Stop already closed this turn (SupportConsoleController#stop_turn); keep its result.
      next if %w[queued running].exclude?(turn_status)

      closed = true

      content = [@text.presence, notice].compact.join("\n\n")
      updates = { "turn_status" => status, "progress" => @progress.to_a }
      if @result
        updates["claude_session_id"] = @result["claude_session_id"]
        updates["code_rev"] = @result["code_rev"]
        updates["lag_seconds"] = @result["lag_seconds"]
        updates["cost_usd"] = @result["cost_usd"]
        # H10 — summed per conversation in the composer footer
        updates["usage"] = @result["usage"] if @result["usage"].is_a?(Hash)
      end
      @message.update!(content: content.presence || "…", metadata: (@message.metadata || {}).merge(updates))
    end
    # Nothing to tell the page when another path (Stop, or an earlier finish) closed the turn.
    return unless closed

    # Retention runs on the session's updated_at.
    @session.touch
    # X33 — this job has just closed the turn itself, so the Stop guard in broadcast does not apply
    broadcast(final: true)
    broadcast_composer
  end

  # Re-enables Ask, hides Stop and refreshes the lag / code-version footer once a turn ends.
  def broadcast_composer
    safely_broadcast("composer") do
      Turbo::StreamsChannel.broadcast_replace_to(
        [@session, :support_console],
        target: "support-console-composer",
        partial: "support_console/composer",
        locals: { entity: @entity, session: @session, messages: @session.agent_chat_messages.order(:id).to_a }
      )
    end
  end

  def update_metadata(updates)
    @message.update!(metadata: (@message.metadata || {}).merge(updates))
  end

  # Re-renders the assistant message in the open page.
  #
  # @param final [Boolean] true only from finish, which has just closed the turn under the lock
  def broadcast(final: false)
    # E9 — once Stop has closed the turn, a late event must not bring the spinner back. X33 — finish's
    # own update would read as "closed elsewhere" here, so it skips the check.
    return if !final && closed_elsewhere?

    # The in-flight text and progress go in as locals: the stored row only changes in finish.
    metadata = (@message.metadata || {}).merge("progress" => @progress.to_a)
    safely_broadcast("message") do
      Turbo::StreamsChannel.broadcast_replace_to(
        [@session, :support_console],
        target: ActionView::RecordIdentifier.dom_id(@message),
        partial: "support_console/message",
        locals: { message: @message, content: @text.presence || @message.content, metadata: metadata }
      )
    end
  end

  # @return [Boolean] whether the turn was closed outside this job (Stop), checked from the database
  def closed_elsewhere?
    %w[queued running].exclude?(AgentChatMessage.where(id: @message.id).pick(:metadata)&.dig("turn_status"))
  end

  # A live update is a convenience: the answer is in the database and a reload shows it. A failed
  # render (e.g. a Sidekiq started before a helper was added) is reported once per turn and never
  # fails the turn or stops Claude mid-investigation.
  def safely_broadcast(what)
    yield
  rescue StandardError => e
    return if @broadcast_failed

    @broadcast_failed = true
    log_failure(e)
    ErrorReport.notify(e, job: self, broadcast: what, entity_id: @entity&.id, agent_chat_session_id: @session&.id,
                          agent_chat_message_id: @message&.id)
  end

  # @return [User, nil] who asked this turn's question; turns queued before asked_by_id was stored
  #   fall back to the conversation's starter, the only person who could ask then
  def asker
    asked_by_id = @message.metadata&.dig("asked_by_id")
    asked_by_id ? User.find_by(id: asked_by_id) : @session.analyst
  end

  # @return [String] the conversation's key on the machine
  def session_key
    "#{@entity.id}:#{@session.id}"
  end

  # @return [String] the user message this turn answers
  def question
    @session.agent_chat_messages.where(role: "user").where(id: ...@message.id).order(:id).last&.content.to_s
  end

  # H3 — follow-ups resume the Claude Code session of the last turn that started one (X25: a stopped
  # turn's session too, so its context is not lost).
  #
  # @return [String, nil]
  def resume_id
    previous = @session.agent_chat_messages.where(role: "assistant").where(id: ...@message.id).order(id: :desc)
    previous.find { |m| m.metadata&.dig("claude_session_id").present? }&.metadata&.dig("claude_session_id")
  end

  def turn_status
    @message.metadata&.dig("turn_status")
  end

  def stop_quietly
    SupportConsoleRelayClient.new.stop(session_key)
  rescue SupportConsoleRelayClient::Error => e
    log_failure(e)
  end

  def log_failure(error)
    Rails.logger.warn("[support_console] entity=#{@entity&.id} session=#{@session&.id} message=#{@message&.id} #{error.class}: #{error.message}")
  end

  def report(error)
    log_failure(error)
    ErrorReport.notify(error, job: self, entity_id: @entity&.id, agent_chat_session_id: @session&.id, agent_chat_message_id: @message&.id)
  end
end
