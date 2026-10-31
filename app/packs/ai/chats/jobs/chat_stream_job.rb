class ChatStreamJob < ApplicationJob
  queue_as :default

  # Number of chunks after which we force a full re-render
  CHUNK_RENDER_INTERVAL = 5

  # What the answer says when the model returned nothing (E15).
  FALLBACK_ANSWER = "The assistant was unable to generate a response. This may be due to complex constraints or a " \
                    "temporary connection issue. Please try rephrasing your request.".freeze

  # Main job entry point. The page already shows the question and a pending answer
  # (chats/send_message.turbo_stream); this streams the answer into that pending one on the chat kit
  # (ai_chat/_answer), then re-renders the question box.
  #
  # @param chat_id [Integer] ID of the Chat to stream into
  # @param user_content [String] The message content from the user
  # @param document_id [Integer, nil] Optional ID of the Document to include in context
  # @param request_id [String, nil] the pending answer's id on the page (chat_response_<request_id>)
  def perform(chat_id, user_content, document_id: nil, request_id: nil)
    @chat = Chat.find(chat_id)
    @request_id = request_id
    @chunk_counter = 0

    begin
      # Load the document if provided and valid — only one of the chat's own record's documents (the ones
      # the picker offers), never another record's or tenant's by id (X41).
      if document_id.present? && @chat.owner.respond_to?(:documents)
        document = @chat.owner.documents.find_by(id: document_id)
        Rails.logger.debug { "Adding document to chat: #{document&.name}" }
      end

      # Prepare the `with:` options for the chat request
      with = document.present? ? [document.file.download.path] : []

      # Ask the chat and stream the response chunk by chunk
      @chat.ask(user_content, with: with) do |chunk|
        process_chunk(chunk)
      end

      # E15 — an empty answer is saved and shown as the fallback text.
      final_message = @chat.messages.last
      # Message has no role predicates (assistant? etc.); role is stored as a string.
      final_message.update!(content: FALLBACK_ANSWER) if final_message&.role == "assistant" && final_message.content.blank?

      # H5 — the finished answer replaces the streaming one; the box is ready for the next question.
      broadcast_answer(final_message&.content.presence || FALLBACK_ANSWER, status: :answered)
      broadcast_composer
    rescue StandardError => e
      Rails.logger.debug e.backtrace
      # X4 — the user is alerted as before; the answer reads "Not answered" and the question goes back.
      send_notification("Error while streaming chat response: #{e.message}", @chat.user_id, :alert)
      broadcast_answer("Error while streaming chat response: #{e.message}", status: :failed)
      broadcast_composer(value: user_content)
    end
  end

  private

  # Processes a single streamed chunk of the assistant's response
  #
  # @param chunk [Chunk] A streamed response chunk from the chat model
  def process_chunk(chunk)
    assistant_message = @chat.messages.last
    return unless chunk.content.present? && assistant_message

    # Append the chunk content to the full assistant message
    assistant_message.update!(
      content: assistant_message.content.to_s + chunk.content
    )

    @chunk_counter += 1

    # Re-render at sentence or line ends (and every few chunks), so markdown renders cleanly as it grows.
    broadcast_answer(assistant_message.content, status: :running) if render_full_chunk?(chunk)
  end

  # Determines whether we should re-render the full message
  #
  # @param chunk [Chunk] The chunk being processed
  # @return [Boolean] Whether to render the full message
  def render_full_chunk?(chunk)
    (@chunk_counter % CHUNK_RENDER_INTERVAL).zero? ||
      chunk.content.strip.ends_with?(".") ||
      chunk.content.include?("\n")
  end

  # Replaces the pending answer on the page with the answer so far (running), the finished answer, or
  # the failure. Nothing to replace without a request id.
  #
  # @param content [String]
  # @param status [Symbol] :running, :answered or :failed
  def broadcast_answer(content, status:)
    return unless @request_id

    dom_id = "chat_response_#{@request_id}"
    Turbo::StreamsChannel.broadcast_replace_to(
      [@chat, "messages"],
      target: dom_id,
      partial: "ai_chat/answer",
      locals: { item: AiChatItem.transient(dom_id:, role: "assistant", content:, status:), mode: :rich }
    )
  end

  # Re-renders the question box once the answer ends: Ask enabled again, a failed question back in it.
  #
  # @param value [String, nil]
  def broadcast_composer(value: nil)
    return unless @request_id

    Turbo::StreamsChannel.broadcast_replace_to(
      [@chat, "messages"],
      target: "chat-composer",
      partial: "chats/composer",
      locals: { chat: @chat, running: false, value: value }
    )
  end
end
