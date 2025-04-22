class ChatStreamJob < ApplicationJob
  queue_as :default

  def perform(chat_id, user_content)
    chat = Chat.find(chat_id)
    # The `ask` method automatically saves the user message first.
    # It then creates the assistant message record *before* streaming starts,
    # and updates it with the final content/tokens upon completion.
    chat.ask(user_content) do |chunk|
      # Get the latest (assistant) message record, which was created by `ask`
      assistant_message = chat.messages.last
      if chunk.content && assistant_message
        # Append the chunk content to the message's target div
        assistant_message.broadcast_append_chunk(chunk.content)
      end
    end
    # Final assistant message is now fully persisted by acts_as_chat
  end
end
