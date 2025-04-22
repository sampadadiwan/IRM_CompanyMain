class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  # Provides methods like tool_call?, tool_result?
  acts_as_message # Assumes Chat and ToolCall model names

  # Broadcast updates to self (for streaming into the message frame)
  broadcasts_to ->(message) { [message.chat, "messages"] }

  # Helper to broadcast chunks during streaming
  def broadcast_append_chunk(chunk_content)
    html_chunk = ApplicationController.helpers.markdown_to_html(chunk_content)

    Turbo::StreamsChannel.broadcast_append_to(
      [chat, "messages"],               # Stream name
      target: dom_id(self, "content"),  # Append into div#message_123_content
      html: html_chunk                  # Rendered HTML from markdown
    )
  end
  
end
