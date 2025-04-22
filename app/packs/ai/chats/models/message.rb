class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  # Provides methods like tool_call?, tool_result?
  acts_as_message # Assumes Chat and ToolCall model names

  # Broadcast updates to self (for streaming into the message frame)
  broadcasts_to ->(message) { [message.chat, "messages"] }

  # Helper to broadcast chunks during streaming
  def broadcast_append_chunk(chunk_content)
    html_chunk = markdown_to_html(chunk_content)

    broadcast_append_to [chat, "messages"], # Target the stream
                        target: dom_id(self, "content"), # Target the content div inside the message frame
                        html: html_chunk # Append the raw chunk
  end

  def markdown_to_html(text)
    renderer = Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true)
    markdown = Redcarpet::Markdown.new(renderer, {})
    markdown.render(text)
  end
end
