class ChatStreamJob < ApplicationJob
  queue_as :default

  CHUNK_RENDER_INTERVAL = 5

  def perform(chat_id, user_content)
    chat = Chat.find(chat_id)
    chunk_counter = 0

    chat.ask(user_content) do |chunk|
      assistant_message = chat.messages.last

      if chunk.content && assistant_message
        # Update full content
        assistant_message.update!(
          content: assistant_message.content.to_s + chunk.content
        )

        chunk_counter += 1

        if chunk_counter % CHUNK_RENDER_INTERVAL == 0 || chunk.content.strip.ends_with?(".") || chunk.content.include?("\n")

          # Replace full content with markdown-rendered HTML every N chunks
          turbo_stream = ApplicationController.render(
            partial: "messages/streamed_markdown",
            locals: { message: assistant_message }
          )

          Turbo::StreamsChannel.broadcast_to([chat, "messages"], turbo_stream)
        else
          # Fast: Just append chunk as plain text
          Turbo::StreamsChannel.broadcast_append_to(
            [chat, "messages"],
            target: ActionView::RecordIdentifier.dom_id(assistant_message, "content"),
            html: ERB::Util.html_escape(chunk.content)
          )
        end
      end
    end

    # Final render at the end
    assistant_message = chat.messages.last
    turbo_stream = ApplicationController.render(
      partial: "messages/streamed_markdown",
      locals: { message: assistant_message }
    )
    Turbo::StreamsChannel.broadcast_to([chat, "messages"], turbo_stream)
  end
end
