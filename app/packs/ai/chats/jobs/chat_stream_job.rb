class ChatStreamJob < ApplicationJob
  queue_as :default

  # Number of chunks after which we force a full re-render
  CHUNK_RENDER_INTERVAL = 5

  # Main job entry point
  #
  # @param chat_id [Integer] ID of the Chat to stream into
  # @param user_content [String] The message content from the user
  # @param document_id [Integer, nil] Optional ID of the Document to include in context
  def perform(chat_id, user_content, document_id: nil)
    @chat = Chat.find(chat_id)
    @chunk_counter = 0

    begin
      # Load the document if provided and valid
      if document_id.present?
        document = Document.find_by(id: document_id)
        Rails.logger.debug { "Adding document to chat: #{document.name}" }
      end

      # Prepare the `with:` options for the chat request
      options = document.present? ? { pdf: document.file_url } : {}

      # Ask the chat and stream the response chunk by chunk
      @chat.ask(user_content, with: options) do |chunk|
        process_chunk(chunk)
      end

      # Final render to ensure the last message is cleanly displayed
      broadcast_full_message(@chat.messages.last)
    rescue StandardError => e
      send_notification("Error while streaming chat response: #{e.message}", @chat.user_id, :error)
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

    # Conditions for full re-render (better for markdown or sentence ends)
    if render_full_chunk?(chunk)
      broadcast_full_message(assistant_message)
    else
      # Lightweight update: just append the raw chunk HTML-escaped
      Turbo::StreamsChannel.broadcast_append_to(
        [@chat, "messages"],
        target: ActionView::RecordIdentifier.dom_id(assistant_message, "content"),
        html: ERB::Util.html_escape(chunk.content)
      )
    end
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

  # Renders and broadcasts the full assistant message with markdown support
  #
  # @param message [Message] The assistant message to render
  def broadcast_full_message(message)
    turbo_stream = ApplicationController.render(
      partial: "messages/streamed_markdown",
      locals: { message: message }
    )
    Turbo::StreamsChannel.broadcast_to([@chat, "messages"], turbo_stream)
  end
end
